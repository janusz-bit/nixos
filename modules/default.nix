{ inputs, ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  imports = [
    inputs.home-manager.flakeModules.home-manager
    inputs.git-hooks-nix.flakeModule
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

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';

        packages = config.pre-commit.settings.enabledPackages ++ [
          (pkgs.writeShellScriptBin "update-flake" ''
            set -e
            echo "Updating flake inputs..."
            nix flake update
            git add flake.lock
            git commit -m "Update flake.lock"
            echo "Updating proton..."
            ${config.packages.proton-cachyos-v3.updateScript}/bin/update-proton-cachyos
          '')
        ];
      };
    };
}
