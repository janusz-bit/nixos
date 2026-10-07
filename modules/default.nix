{
  inputs,
  self,
  customTop,
  ...
}:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  imports = [
    inputs.flake-parts.flakeModules.modules
    inputs.git-hooks-nix.flakeModule
    inputs.github-actions-nix.flakeModules.default
  ];

  perSystem =
    {
      config,
      lib,
      pkgs,
      self',
      system,
      ...
    }:
    {
      formatter = pkgs.nixfmt-tree;
      # Instalator hosta nixos istnieje tylko dla x86_64 (modules/installer).
      packages.default = lib.mkIf (system == "x86_64-linux") self'.packages.install-system;

      pre-commit.settings.hooks = {
        # git-hooks-nix nie definiuje hooka gitleaks (nigdy nie istniał
        # upstreamowo) — custom hook z jawnym entry, jak w oficjalnej
        # integracji pre-commit gitleaks. --staged jest konieczne: bez niego
        # gitleaks skanuje `git diff` (drzewo robocze vs indeks), a pre-commit
        # przed hookami odkłada niezaindeksowane zmiany — skan był zawsze
        # pusty. Całe drzewo w CI: checks.gitleaks.
        gitleaks = {
          enable = true;
          name = "gitleaks";
          entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --staged --redact --verbose";
          pass_filenames = false;
        };
        nixfmt.enable = true;
        statix.enable = true;
        deadnix = {
          enable = true;
          settings.noLambdaPatternNames = true;
        };
        # UWAGA: entry jest przypięte do store path zbudowanego w momencie
        # wejścia do dev shella. Po zmianie `modules/github-actions.nix` stary
        # hook nadal kopiuje workflowy z POPRZEDNIEJ wersji flake i cofa
        # nowe YAML (objaw: "files were modified by this hook" + stary
        # workflow w commicie — tak powstał incydent v504). Po edycji
        # github-actions.nix: wyjść i wejść ponownie do `nix develop`
        # (albo `SKIP=sync-github-actions git commit` + `nix run .#sync-github-actions`).
        sync-github-actions = {
          enable = true;
          name = "sync-github-actions";
          entry = "${config.packages.sync-github-actions}/bin/sync-github-actions";
          pass_filenames = false;
        };
      };

      checks = {
        # Całe drzewo flake'a (pre-commit w CI widzi pusty diff, a repo jest
        # publiczne). Pliki *.age to zaszyfrowany armor age.
        gitleaks = pkgs.runCommand "gitleaks-tree" { nativeBuildInputs = [ pkgs.gitleaks ]; } ''
          gitleaks dir --redact --no-banner --exit-code 1 ${self}
          touch $out
        '';

        # AGENTS.md: customTop.cache (nix.settings hostów, CI) i nixConfig we
        # flake.nix (pierwszy rebuild, --accept-flake-config) muszą wymieniać
        # te same cache — rozjazd oznacza np. lokalną kompilację kernela.
        cache-config =
          let
            flakeConfig = (import (self + "/flake.nix")).nixConfig;
            caches = [ customTop.cache.cachix ] ++ customTop.cache.inputs;
          in
          assert lib.assertMsg (
            flakeConfig.extra-substituters == map (c: c.url) caches
          ) "flake.nix nixConfig.extra-substituters != customTop.cache";
          assert lib.assertMsg (
            flakeConfig.extra-trusted-public-keys == map (c: c.pubKey) caches
          ) "flake.nix nixConfig.extra-trusted-public-keys != customTop.cache";
          pkgs.runCommand "cache-config" { } "touch $out";

        # Odbiorcy w nagłówkach plików .age == reguły (agenix -c czyta tylko
        # nagłówki, bez kluczy prywatnych). Wykrywa brak rekeyingu po zmianie
        # odbiorców i reguły bez pliku.
        agenix-recipients =
          pkgs.runCommand "agenix-recipients"
            {
              nativeBuildInputs = [
                inputs.agenix.packages.${system}.default
                pkgs.nix
              ];
            }
            ''
              # nix-instantiate --eval reguł bez demona i bez /nix/var w sandboxie
              export HOME=$TMPDIR NIX_REMOTE="local?root=$TMPDIR/nix"
              cd ${customTop.secretsDir}
              AGENIX_RULES=$PWD/agenix-rules.nix agenix -c
              touch $out
            '';
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';

        packages = config.pre-commit.settings.enabledPackages ++ [
          # jq: hook Claude Code (.claude/hooks/post-edit.sh) parsuje nim
          # JSON z wejścia hooka.
          pkgs.jq
          config.packages.flake-update
          config.packages.flake-release
          config.packages.repo-sync
        ];
      };
    };
}
