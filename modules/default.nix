# Szkielet flake'a: systemy, moduły flake-parts (flake.modules, git-hooks,
# github-actions), formatter, hooki pre-commit (gitleaks, nixfmt, statix,
# deadnix, generatory .github/workflows i docs/reference) oraz dev shell,
# w którym te hooki się instalują (`nix develop`, alias claude-nixos).
{ inputs, ... }:
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
      ...
    }:
    let
      # Hook generatora (workflowy CI, docs/reference): lokalnie
      # `nix run .#<generator>` na bieżącym drzewie. Wpis hooka jest przypięty
      # do store path z chwili wejścia do dev shella, więc wołana wprost
      # paczka generowałaby pliki ze STAREJ wersji flake'a i cofała świeże
      # zmiany (tak powstał incydent v504). W piaskownicy checks.pre-commit
      # (CI lint) nie ma nix — tam działa przypięta kopia, zbudowana z tego
      # samego commita, więc też aktualna.
      freshGenerator =
        name:
        lib.getExe (
          pkgs.writeShellApplication {
            name = "${name}-hook";
            text = ''
              if command -v nix >/dev/null; then
                exec nix run ".#${name}"
              fi
              exec ${lib.getExe config.packages.${name}}
            '';
          }
        );
    in
    {
      formatter = pkgs.nixfmt-tree;
      packages.default = self'.packages.install-system;

      pre-commit.settings.hooks = {
        # git-hooks-nix nie definiuje hooka gitleaks (nigdy nie istniał
        # upstreamowo) — custom hook z jawnym entry, jak w oficjalnej
        # integracji pre-commit gitleaks (skan staged diff; pliki sekretów
        # *.age są zaszyfrowane i nie dają się sensownie skanować).
        gitleaks = {
          enable = true;
          name = "gitleaks";
          entry = "${lib.getExe pkgs.gitleaks} git --pre-commit --redact --verbose";
          pass_filenames = false;
        };
        nixfmt.enable = true;
        statix.enable = true;
        deadnix = {
          enable = true;
          settings.noLambdaPatternNames = true;
        };
        sync-github-actions = {
          enable = true;
          name = "sync-github-actions";
          entry = freshGenerator "sync-github-actions";
          # Workflowy zależą od rejestru hostów, args.nix i nixConfig.
          files = "^(flake\\.(nix|lock)|modules/(args|github-actions)\\.nix|modules/hosts/.*|\\.github/workflows/.*)$";
          pass_filenames = false;
        };
        sync-docs = {
          enable = true;
          name = "sync-docs";
          entry = freshGenerator "sync-docs";
          files = "^(modules/.*\\.nix|docs/reference/.*)$";
          pass_filenames = false;
        };
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
