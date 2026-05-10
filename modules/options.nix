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
    };
  _module.args.custom = rec {
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
      atticIp = "192.168.100.212";
    };
    secretsDir = self + "/modules/_secrets";
  };
}
