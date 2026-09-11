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
      pkgs,
      self',
      ...
    }:
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
          entry = "${pkgs.gitleaks}/bin/gitleaks git --pre-commit --redact --verbose";
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

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';

        packages = config.pre-commit.settings.enabledPackages ++ [
          config.packages.flake-update
          config.packages.flake-release
          config.packages.repo-sync
        ];
      };
    };
}
