# Generator workflowów GitHub Actions (github-actions-nix): build toplevelu
# każdego hosta z rejestru, obraz SD RPi, ewaluacja
# wszystkich hostów, lint (pre-commit) i ręczna aktualizacja kernela CachyOS.
#
# .github/workflows/*.yml to wynik tego pliku: `nix run .#sync-github-actions`
# (też hook pre-commit przy każdym commicie) nadpisuje je i usuwa workflowy,
# których już nie ma. Nowy host w rejestrze nie wymaga zmian tutaj.
#
# Akcje są przypięte do SHA commitów, nie tagów: tag można przesunąć na inny
# kod, a akcje widzą CACHIX_AUTH_TOKEN, w cachyos-kernel-update także
# `contents: write` (push flake.lock), a w workflowach z cache'em w tailnecie
# (hosts/nix-cache.nix) `id-token: write` (logowanie OIDC do Tailscale).
#
# Sprawdzenie: `nix run .#sync-github-actions && git status --short .github/workflows`
# (pusto = workflowy w repo zgodne z generatorem).
{
  config,
  lib,
  ...
}:
let
  # Rejestr hostów (modules/hosts/registry.nix) i customTop (modules/args.nix);
  # perSystem ma własne `config`.
  inherit (config) hosts customTop;
in
{
  perSystem =
    { config, pkgs, ... }:
    let
      # Nowy SHA: `git ls-remote https://github.com/<repo> 'refs/tags/<tag>^{}' 'refs/tags/<tag>'`.
      actions = {
        checkout = "actions/checkout@fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09"; # v5
        installNix = "cachix/install-nix-action@13d8dd58da0234aa297dedd986986ccb8e7f3e24"; # v31
        cachix = "cachix/cachix-action@18cf96c7c98e048e10a83abd92116114cd8504be"; # v14
        tailscale = "tailscale/github-action@064b10558093f38325e838ddea35486bdc6b1d5c"; # v4.4.0
      };

      # Hosty, które pobierają z cache'a w tailnecie (hosts/nix-cache.nix): ich
      # buildy dołączają do tailnetu, biorą z niego i wysyłają tam wynik.
      nixCacheHosts = [
        "nixos"
        "raspberry-pi-4"
      ];

      archToRunner = {
        x86_64-linux = "ubuntu-latest";
        aarch64-linux = "ubuntu-24.04-arm";
      };

      # cachedBy: świat x86-64-v3 laptopa leży w cache'u RPi podpisany kluczem
      # nixpkgs-v3, więc tylko jego build ufa temu kluczowi (jak sam laptop).
      baseSteps =
        nixCache: cachedBy:
        let
          substituters = [ customTop.cachix.url ] ++ lib.optional nixCache customTop.nixCache.url;
          publicKeys = [
            customTop.cachix.pubKey
          ]
          ++ lib.optional nixCache customTop.nixCache.publicKey
          ++ lib.optional (cachedBy != null) customTop.nixCache.v3PublicKey;
        in
        [
          {
            name = "Checkout repository";
            uses = actions.checkout;
          }
          {
            name = "Install Nix";
            uses = actions.installNix;
            with_.extra_nix_config = ''
              experimental-features = nix-command flakes
              access-tokens = github.com=''${{ secrets.GITHUB_TOKEN }}
              extra-substituters = ${lib.concatStringsSep " " substituters}
              extra-trusted-public-keys = ${lib.concatStringsSep " " publicKeys}
              build-fallback = true
            ''
            # Jak na laptopie (nixos-nix-cache): RPi poza siecią nie wstrzymuje
            # buildu na limicie curl.
            + lib.optionalString nixCache "connect-timeout = 5\n";
          }
        ]
        # continue-on-error: bez tailnetu build idzie dalej, tylko bez cache'a RPi.
        ++ lib.optional nixCache {
          name = "Connect to the tailnet";
          uses = actions.tailscale;
          continueOnError = true;
          with_ = {
            oauth-client-id = "\${{ secrets.TS_OAUTH_CLIENT_ID }}";
            audience = "\${{ secrets.TS_AUDIENCE }}";
            tags = "tag:ci";
          };
        }
        ++ [
          {
            name = "Setup Cachix";
            uses = actions.cachix;
            with_ = {
              inherit (customTop.cachix) name;
              authToken = "\${{ secrets.CACHIX_AUTH_TOKEN }}";
            };
          }
        ];

      # Po buildzie, wynik w ./result*. Sekrety tylko w env tego kroku;
      # niedostępny cache daje ostrzeżenie zamiast nieudanego buildu.
      nixCachePush = {
        name = "Push to the tailnet nix cache";
        continueOnError = true;
        env = {
          NIX_CACHE_SIGNING_KEY = "\${{ secrets.NIX_CACHE_SIGNING_KEY }}";
          NIX_CACHE_PUSH_PASSWORD = "\${{ secrets.NIX_CACHE_PUSH_PASSWORD }}";
        };
        run = "nix run .#nix-cache-push -- ./result*";
      };

      mkWorkflow =
        name:
        {
          arch,
          buildTarget ? "nixosConfigurations.${name}.config.system.build.toplevel",
          runName ? "Build ${name} by @\${{ github.actor }}",
          command ? "nix build \".#${buildTarget}\" --show-trace --accept-flake-config",
          # false: buildy 3-5 h (host nixos) padają głównie na infrastrukturze
          # CI (cache.nixos.org, limity api.github.com), więc ruszają tylko przy
          # PR i ręcznie, nie przy v*.
          tags ? true,
          # Tanie sprawdzenia także na każdy push do master (commity trafiają
          # tam wprost).
          onMaster ? false,
          # Dołącza do tailnetu, pobiera z cache'a RPi i wysyła do niego wynik.
          nixCache ? false,
          # hosts.<host>.cachedBy: zamknięcie buduje CI innego repo (świat
          # x86-64-v3 to tysiące derywacji, żaden 6-godzinny job go nie
          # zbuduje). Build tylko, gdy tamto repo ma tag cached/nixos-<sha>
          # (komplet w cache'u RPi), inaczej dry run z liczbą brakujących
          # derywacji i ostrzeżeniem.
          cachedBy ? null,
        }:
        let
          gated = lib.concatStringsSep "\n" [
            "sha=\${{ github.event.pull_request.head.sha || github.sha }}"
            "if git ls-remote --exit-code https://github.com/${cachedBy} \"refs/tags/cached/nixos-$sha\" >/dev/null; then"
            "  ${command}"
            "else"
            "  missing=$(nix build \".#${buildTarget}\" --dry-run --accept-flake-config 2>&1 | grep -c '\\.drv$' || true)"
            "  echo \"::warning::${cachedBy} has no cached/nixos-$sha yet: $missing derivations are in no cache. Build them there: gh workflow run build.yml --repo ${cachedBy} -f nixos_ref=$sha\""
            "  echo \"$missing derivations of ${name} are not cached yet (${cachedBy}, cached/nixos-$sha missing); build skipped.\" >> \"$GITHUB_STEP_SUMMARY\""
            "fi"
          ];
        in
        {
          inherit name runName;
          # Least privilege: buildy tylko czytają repo; id-token to logowanie
          # OIDC do Tailscale.
          permissions = {
            contents = "read";
          }
          // lib.optionalAttrs nixCache { id-token = "write"; };
          concurrency.group = "build-${name}-\${{ github.ref }}";
          on = {
            push = lib.mkIf (tags || onMaster) {
              tags = lib.mkIf tags [ "v*" ];
              branches = lib.mkIf onMaster [ "master" ];
            };
            pullRequest.branches = [ "master" ];
            workflowDispatch = { };
          };
          jobs.build = {
            runsOn = archToRunner.${arch};
            steps =
              baseSteps nixCache cachedBy
              ++ [
                {
                  inherit name;
                  run = if cachedBy == null then command else gated;
                }
              ]
              ++ lib.optional nixCache nixCachePush;
          };
        };
    in
    {
      packages = {
        github-actions = config.githubActions.workflowsDir;

        sync-github-actions = pkgs.writeShellApplication {
          name = "sync-github-actions";
          runtimeInputs = [
            pkgs.coreutils
            pkgs.findutils
          ];
          text = ''
            workflows=${lib.escapeShellArg config.githubActions.workflowsDir}
            echo "Syncing workflows from $workflows to .github/workflows/..."
            mkdir -p .github/workflows
            # Usun stare workflowy, ktore nie sa juz generowane (np. po refactorze),
            # zeby nie zostaly osierocone pliki w .github/workflows/.
            find .github/workflows -name '*.yml' -delete
            cp -f "$workflows"/*.yml .github/workflows/
            chmod +w .github/workflows/*.yml
            echo "Done! Workflows are now in sync."
          '';
        };
      };

      githubActions = {
        enable = true;
        workflows =
          lib.mapAttrs mkWorkflow (
            lib.mapAttrs (name: host: {
              arch = host.system;
              tags = host.buildOnTags;
              nixCache = lib.elem name nixCacheHosts;
              inherit (host) cachedBy;
            }) hosts
            // {
              raspberry-pi-4-sd-image = {
                arch = "aarch64-linux";
                buildTarget = "packages.aarch64-linux.raspberry-pi-4-sd-image";
              };
              eval = {
                arch = "x86_64-linux";
                runName = "Evaluate hosts by @\${{ github.actor }}";
                onMaster = true;
                command = lib.concatMapStringsSep "\n" (
                  host:
                  "nix eval --raw .#nixosConfigurations.${host}.config.system.build.toplevel.drvPath --show-trace --accept-flake-config"
                ) (lib.attrNames hosts);
              };
              lint = {
                arch = "x86_64-linux";
                buildTarget = "checks.x86_64-linux.pre-commit";
                onMaster = true;
              };
            }
          )
          // {
            cachyos-kernel-update = {
              name = "cachyos-kernel-update";
              runName = "Update & Build CachyOS Kernel by @\${{ github.actor }}";
              on.workflowDispatch = { };
              permissions = {
                contents = "write";
                id-token = "write";
              };
              # Ręcznie odpalany: dwa równoległe buildy kernela nie mają sensu.
              concurrency.group = "cachyos-kernel-update";
              jobs.update-and-build = {
                runsOn = archToRunner.x86_64-linux;
                steps = baseSteps true null ++ [
                  {
                    name = "Update nix-cachyos-kernel flake input";
                    run = "nix flake update nix-cachyos-kernel";
                  }
                  {
                    name = "Build Kernel";
                    run = "nix build \".#nixosConfigurations.nixos.config.boot.kernelPackages.kernel^*\" --show-trace --accept-flake-config";
                  }
                  nixCachePush
                  {
                    name = "Commit updated flake.lock";
                    run = ''
                      git config user.name "github-actions[bot]"
                      git config user.email "github-actions[bot]@users.noreply.github.com"
                      git add flake.lock
                      git diff --cached --quiet || git commit -m "flake.lock: update nix-cachyos-kernel"
                      git push
                    '';
                  }
                ];
              };
            };
          };
      };
    };
}
