# This module serves as the central source of truth for custom configuration options
# and global arguments used across the entire Nix flake. It provides a single, unified
# place to manage repository details, domain names, local network IPs (e.g., Attic cache),
# and default user settings (`options.custom` and `_module.args.custom`).
{ self, inputs, ... }:
{
  flake.modules.nixos.options =
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
}
