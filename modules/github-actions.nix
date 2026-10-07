{ customTop, ... }:
{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      # Akcje przypięte do commitów (tag można przesunąć — a akcje widzą
      # CACHIX_AUTH_TOKEN i w cachyos-kernel-update mają contents: write).
      # Bump: `git ls-remote https://github.com/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`.
      actions = {
        checkout = "actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"; # v5
        installNix = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"; # v31
        # v17: node24 (v14 deklarował wycofany node20).
        cachix = "cachix/cachix-action@38b082610b782e7e93e209c35fd730d399dee866"; # v17
      };

      # Wszystkie cache z customTop — te same co nix.settings hostów i
      # nixConfig we flake.nix (checks.cache-config pilnuje zgodności), więc
      # CI nie zależy od --accept-flake-config przy substitutorach.
      caches = [ customTop.cache.cachix ] ++ customTop.cache.inputs;

      # Obrazy (ext4 rootfs, karta SD, ISO, squashfs) nie są pobierane przez
      # żaden host — nie zapychają limitu Cachix.
      imagePushFilter = "(-ext4-fs\\.img|-nixos-image-sd-card-[^/]*|-nixos-installer[^/]*\\.iso|-squashfs\\.img)$";

      # Wspolne kroki dla wszystkich workflowow budujacych
      mkBaseSteps =
        {
          # Tylko workflow, który pushuje commit (cachyos-kernel-update),
          # zostawia token w .git/config; pozostałe kroki go nie potrzebują.
          persistCredentials ? false,
          # Ciężkie buildy x86 (nixos, kernel): obraz runnera ma ~20 GB
          # wolnego, a domknięcie hosta nixos z lokalnym kernelem się nie mieści.
          freeDiskSpace ? false,
        }:
        lib.optional freeDiskSpace {
          name = "Free disk space";
          run = ''
            df -h /
            sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL /usr/local/share/boost
            sudo docker image prune --all --force
            df -h /
          '';
        }
        ++ [
          {
            name = "Checkout repository";
            uses = actions.checkout;
            with_.persist-credentials = persistCredentials;
          }
          {
            name = "Install Nix";
            uses = actions.installNix;
            # experimental-features (nix-command flakes) i access-tokens
            # z github.token dodaje sama akcja (install-nix.sh); KVM też.
            with_.extra_nix_config = ''
              extra-substituters = ${lib.concatMapStringsSep " " (c: c.url) caches}
              extra-trusted-public-keys = ${lib.concatMapStringsSep " " (c: c.pubKey) caches}
              build-fallback = true
            '';
          }
          {
            name = "Setup Cachix";
            uses = actions.cachix;
            with_ = {
              inherit (customTop.cache.cachix) name;
              authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
              pushFilter = imagePushFilter;
            };
          }
        ];

      evalCommand =
        targets:
        lib.concatMapStringsSep "\n" (
          t: "nix eval --raw .#${t}.drvPath --show-trace --accept-flake-config"
        ) targets;

      hostToplevels = map (h: "nixosConfigurations.${h}.config.system.build.toplevel") [
        "nixos"
        "raspberry-pi-4"
        "wsl"
      ];

      # Workflow aktualizujacy i budujacy CachyOS kernel
      mkCachyOSKernelUpdateWorkflow =
        { name, runsOn }:
        {
          inherit name;
          runName = "Update & Build CachyOS Kernel by @\${{ github.actor }}";
          on = {
            # Na razie wylaczone — daily cron zakomentowany
            # schedule = [ { cron = "0 2 * * *"; } ];
            workflowDispatch = { };
          };
          permissions.contents = "write";
          # Recznie odpalany workflow — bez sensu dwa rownolegle buildy kernela
          concurrency = {
            group = "cachyos-kernel-update";
            cancelInProgress = false;
          };
          jobs.update-and-build = {
            inherit runsOn;
            timeoutMinutes = 360;
            steps =
              mkBaseSteps {
                persistCredentials = true;
                freeDiskSpace = true;
              }
              ++ [
                {
                  name = "Update nix-cachyos-kernel flake input";
                  run = "nix flake update nix-cachyos-kernel";
                }
                {
                  # Bump przesuwa też przypięty nixpkgs inputu, który decyduje
                  # o sterowniku NVIDIA — kernel bez modułów to za mało, bo
                  # push na master = wdrożenie (`update` na laptopie).
                  name = "Build kernel and all kernel modules (incl. NVIDIA)";
                  run = ''
                    nix build --show-trace --accept-flake-config \
                      ".#nixosConfigurations.nixos.config.boot.kernelPackages.kernel^*" \
                      ".#nixosConfigurations.nixos.config.system.modulesTree"
                  '';
                }
                {
                  name = "Evaluate all hosts";
                  run = evalCommand hostToplevels;
                }
                {
                  # Push GITHUB_TOKEN-em nie uruchamia innych workflowów, więc
                  # weryfikacja musi być tutaj; rebase, bo build trwa godzinami
                  # i master mógł się przesunąć (wcześniej: non-fast-forward).
                  # Gdy rebase coś zmienił, kombinacja jest budowana i
                  # ewaluowana jeszcze raz przed pushem (bez zmian w kernelu
                  # to szybkie no-opy z cache).
                  name = "Commit updated flake.lock and push";
                  run = ''
                    git config user.name "github-actions[bot]"
                    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
                    git add flake.lock
                    if git diff --cached --quiet; then
                      echo "flake.lock unchanged"
                      exit 0
                    fi
                    git commit -m "flake.lock: update nix-cachyos-kernel"
                    before="$(git rev-parse HEAD)"
                    git pull --rebase origin "''${GITHUB_REF_NAME}"
                    if [ "$(git rev-parse HEAD)" != "$before" ]; then
                      echo "master moved during the build; re-verifying the rebased commit"
                      nix build --show-trace --accept-flake-config \
                        ".#nixosConfigurations.nixos.config.boot.kernelPackages.kernel^*" \
                        ".#nixosConfigurations.nixos.config.system.modulesTree"
                      ${evalCommand hostToplevels}
                    fi
                    git push origin "HEAD:''${GITHUB_REF_NAME}"
                  '';
                }
              ];
          };
        };

      # Fabryka workflowow
      mkBuildWorkflow =
        {
          name,
          buildTarget,
          runsOn,
          runName ? "Build ${name} by @\${{ github.actor }}",
          command ? null,
          # `tags = false` dla ciezkich buildow. Build toplevela `nixos` trwa
          # 3-5 h i w wiekszosci pada na infrastrukturze CI (cache.nixos.org,
          # limity api.github.com), wiec nie odpalamy go przy kazdym tagu —
          # zostaje PR + reczny workflow_dispatch.
          tags ? true,
          # Tanie sprawdzenia (lint, ewaluacja) odpalaja sie tez na kazdy
          # push do master — commity trafiaja tam bezposrednio.
          onMaster ? false,
          # Domyślne 360 min GitHuba trzymało zawieszony eval/lint godzinami.
          timeoutMinutes,
          freeDiskSpace ? false,
        }:
        {
          inherit name runName;
          # Least privilege: buildy tylko czytaja repo.
          permissions.contents = "read";
          # Ten sam workflow dla tego samego refa nie odpala sie dwa razy.
          # cancelInProgress = false — nie zabijamy buildow w trakcie.
          concurrency = {
            group = "build-${name}-\${{ github.ref }}";
            cancelInProgress = false;
          };
          on = {
            push =
              if tags || onMaster then
                (if tags then { tags = [ "v*" ]; } else { })
                // (if onMaster then { branches = [ "master" ]; } else { })
              else
                null;
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs.build = {
            inherit runsOn timeoutMinutes;
            steps = mkBaseSteps { inherit freeDiskSpace; } ++ [
              {
                inherit name;
                run =
                  if command == null then
                    "nix build \".#${buildTarget}\" --show-trace --accept-flake-config"
                  else
                    command;
              }
            ];
          };
        };

      # Mapa architektur na GitHub Runners
      archToRunner = {
        "x86_64-linux" = "ubuntu-latest";
        "aarch64-linux" = "ubuntu-24.04-arm";
      };

      # Ewaluacja (sekundy zamiast godzin buildu) wszystkiego, czego nie
      # buduje żaden workflow przy każdym pushu: hosty, instalator
      # (`nix run github:janusz-bit/nixos`), ISO, obraz SD, pakiety lokalne,
      # devShelle.
      evalTargets =
        hostToplevels
        ++ [
          "packages.x86_64-linux.default"
          "packages.x86_64-linux.post-install"
          "packages.x86_64-linux.nixos-iso"
          "packages.aarch64-linux.raspberry-pi-4-sd-image"
        ]
        ++
          lib.concatMap
            (
              system:
              map (p: "packages.${system}.${p}") [
                "bootdev-cli"
                "waywallen"
                "waywallen-kde-plugin"
              ]
              ++ [ "devShells.${system}.default" ]
            )
            [
              "x86_64-linux"
              "aarch64-linux"
            ];

      # Testy repo (modules/checks, installer) — x86_64 z KVM (install-nix-action).
      checkTargets = map (c: ".#checks.x86_64-linux.${c}") [
        "pre-commit"
        "gitleaks"
        "cache-config"
        "agenix-recipients"
        "installer-scripts"
        "pwm-fan"
        "hermes-activation"
        "rpi-services"
      ];

    in
    {
      packages.github-actions = config.githubActions.workflowsDir;

      packages.sync-github-actions = pkgs.writeShellApplication {
        name = "sync-github-actions";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          WORKFLOWS_DIR="${config.githubActions.workflowsDir}"
          echo "Syncing workflows from $WORKFLOWS_DIR to .github/workflows/..."
          mkdir -p .github/workflows
          # Usun stare workflowy, ktore nie sa juz generowane (np. po refactorze),
          # zeby nie zostaly osierocone pliki w .github/workflows/.
          find .github/workflows -name '*.yml' -delete
          cp -f "$WORKFLOWS_DIR"/*.yml .github/workflows/
          chmod +w .github/workflows/*.yml
          echo "Done! Workflows are now in sync."
        '';
      };

      githubActions = {
        enable = true;
        # Automatycznie generujemy workflowy dla wszystkich wpisow w 'configs'
        workflows =
          builtins.mapAttrs
            (
              name: cfg:
              mkBuildWorkflow {
                inherit name;
                runsOn = archToRunner."${cfg.arch}";
                buildTarget =
                  cfg.buildTarget or "nixosConfigurations.${name}.config.system.build.${cfg.target or "toplevel"}";
                command = cfg.command or null;
                runName = cfg.runName or "Build ${name} by @\${{ github.actor }}";
                tags = cfg.tags or true;
                onMaster = cfg.onMaster or false;
                inherit (cfg) timeoutMinutes;
                freeDiskSpace = cfg.freeDiskSpace or false;
              }
            )
            {
              nixos = {
                arch = "x86_64-linux";
                # Ciezki build (~400 pakietow, 3-5 h) — tylko PR i dispatch.
                tags = false;
                timeoutMinutes = 360;
                freeDiskSpace = true;
              };
              raspberry-pi-4 = {
                arch = "aarch64-linux";
                timeoutMinutes = 240;
              };
              raspberry-pi-4-sd-image = {
                arch = "aarch64-linux";
                buildTarget = "packages.aarch64-linux.raspberry-pi-4-sd-image";
                timeoutMinutes = 300;
              };
              nixos-iso = {
                arch = "x86_64-linux";
                runName = "Evaluate nixos-iso by @\${{ github.actor }}";
                # ISO zawiera całe domknięcie hosta nixos (~52 GiB) plus
                # ~17 GB squashfs i ISO w jednej derywacji — nie mieści się na
                # standardowym runnerze (ENOSPC w mksquashfs). Tu tylko
                # ewaluacja; ISO buduje się lokalnie na laptopie, gdzie
                # domknięcie już jest w store (AGENTS.md).
                command = evalCommand [ "packages.x86_64-linux.nixos-iso" ];
                tags = false;
                timeoutMinutes = 30;
              };
              wsl = {
                arch = "x86_64-linux";
                timeoutMinutes = 120;
              };
              eval = {
                arch = "x86_64-linux";
                runName = "Evaluate flake outputs by @\${{ github.actor }}";
                onMaster = true;
                # Tag wydania wskazuje commit z master, już sprawdzony.
                tags = false;
                command = evalCommand evalTargets;
                timeoutMinutes = 45;
              };
              lint = {
                arch = "x86_64-linux";
                runName = "Lint and test by @\${{ github.actor }}";
                onMaster = true;
                tags = false;
                # --keep-going: każdy check raportuje wynik, nawet gdy inny pada.
                command = "nix build ${lib.concatStringsSep " " checkTargets} --keep-going --show-trace --accept-flake-config -L";
                timeoutMinutes = 90;
              };
            }
          // {
            cachyos-kernel-update = mkCachyOSKernelUpdateWorkflow {
              name = "cachyos-kernel-update";
              runsOn = archToRunner."x86_64-linux";
            };
          };
      };
    };
}
