# Szkielet flake'a: systemy, moduły flake-parts (flake.modules, git-hooks,
# github-actions), formatter, hooki pre-commit (gitleaks, nixfmt, statix,
# deadnix, generatory .github/workflows i docs/reference) oraz dev shell,
# w którym te hooki się instalują (`nix develop`, alias claude-nixos).
#
# Sprawdzenie: `nix develop -c pre-commit run --all-files`; to samo w CI:
# `nix build .#checks.x86_64-linux.pre-commit` (oblewa nieaktualne pliki
# generowane).
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
      system,
      ...
    }:
    let
      # Hook generatora woła `nix run .#<generator>` na bieżącym drzewie, bo
      # wpis hooka jest przypięty do store path z chwili wejścia do dev shella:
      # przypięta paczka generowałaby pliki ze starej wersji flake'a i cofała
      # świeże zmiany (tak stary hook cofnął nowe workflowy w v504).
      # W piaskownicy checks.pre-commit (CI lint) nie ma nix, więc tam działa
      # przypięta kopia z tego samego commita.
      generatorHook = name: {
        enable = true;
        entry = lib.getExe (
          pkgs.writeShellApplication {
            name = "${name}-hook";
            text = ''
              if command -v nix >/dev/null; then
                exec nix run ${lib.escapeShellArg ".#${name}"}
              fi
              exec ${lib.getExe config.packages.${name}}
            '';
          }
        );
        # Przy każdym commicie: filtr plików pomijałby commity z samymi
        # usunięciami (pre-commit nie przekazuje usuniętych plików), a wynik
        # zależy też od flake.lock. Generator nie ewaluuje hostów (~7 s na RPi).
        always_run = true;
        pass_filenames = false;
      };
    in
    {
      # allowUnfree jak na hostach (base-nix): domyślne pkgs flake-parts to
      # legacyPackages nixpkgs, które odmawia ewaluacji pakietów niewolnych,
      # więc packages.<system> (pakiety lokalne, package-import, nix-update)
      # nie mogłyby zawierać np. pakietów CUDA.
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      formatter = pkgs.nixfmt-tree;
      packages.default = config.packages.install-system;

      pre-commit.settings.hooks = {
        gitleaks.enable = true;
        nixfmt.enable = true;
        statix.enable = true;
        deadnix.enable = true;
        deadnix.settings.noLambdaPatternNames = true;
        sync-github-actions = generatorHook "sync-github-actions";
        sync-docs = generatorHook "sync-docs";
      };

      devShells.default = pkgs.mkShell {
        shellHook = config.pre-commit.installationScript;

        packages = config.pre-commit.settings.enabledPackages ++ [
          # jq: .claude/hooks/post-edit.sh parsuje nim JSON hooka Claude Code.
          pkgs.jq
          config.packages.flake-update
          config.packages.flake-release
          config.packages.package-import
          config.packages.repo-sync
        ];
      };
    };
}
