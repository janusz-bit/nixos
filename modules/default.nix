{ inputs, ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  imports = [
    inputs.home-manager.flakeModules.home-manager
    inputs.git-hooks-nix.flakeModule
    inputs.github-actions-nix.flakeModules.default
    ./github-actions.nix
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

      pre-commit.settings.hooks.nixfmt.enable = true;
      pre-commit.settings.hooks.sync-github-actions = {
        enable = true;
        name = "sync-github-actions";
        entry = "${config.packages.sync-github-actions}/bin/sync-github-actions";
        pass_filenames = false;
      };

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';

        packages = config.pre-commit.settings.enabledPackages ++ [
          config.packages.update-flake
        ];
      };
    };
}
