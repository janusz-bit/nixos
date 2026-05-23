# This module serves as the central source of truth for custom configuration options
# and global arguments used across the entire Nix flake. It provides a single, unified
# place to manage repository details, domain names, local network IPs (e.g., Attic cache),
# and default user settings (`options.custom` and `_module.args.custom`).
{ self, inputs, ... }:
{
  flake.nixosModules."options" =
    { lib, config, ... }:
    {
      options.custom.flakeTarget = lib.mkOption {
        type = lib.types.str;
        default = "default";
      };
      options.custom.enableFastfetch = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      options.custom.defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "nixos";
      };
      options.custom.enableOpenWebUi = lib.mkOption {
        type = lib.types.bool;
        default = false;
      };
    };
  _module.args.custom = rec {
    enableOpenWebUi = false;
    repository = {

      name = "nixos";
      site = "github";
      user = "janusz-bit";
      linkFlake = "${repository.site}" + ":" + "${repository.user}" + "/" + "${repository.name}";
      url = "https://${repository.site}.com/${repository.user}/${repository.name}.git";
      place = "/etc/nixos";
    };
    email.full = "janusz-bit@proton.me";
    site = rec {
      name = "janusz-bit";
      end = "com";
      full = name + "." + end;
    };
    cache = rec {
      cachix = rec {
        name = "janusz-bit";
        url = "https://${name}.cachix.org";
        pubKey = "${name}.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo=";
      };
    };
    secretsDir = self + "/modules/_secrets";
  };
}
