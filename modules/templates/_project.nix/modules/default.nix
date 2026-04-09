{ inputs, ... }:
{
  systems = [
    "x86_64-linux"
    "aarch64-linux"
  ];

  imports = [
    inputs.git-hooks-nix.flakeModule
  ];

  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    {
      formatter = pkgs.nixfmt-tree;

      pre-commit.settings.hooks.nixfmt.enable = true;

      devShells.default = pkgs.mkShell {
        shellHook = ''
          ${config.pre-commit.installationScript}
        '';

        packages = config.pre-commit.settings.enabledPackages ++ [
          # add packages to use in shell
        ];
      };
    };
}
