{ self, inputs, ... }:
{
  flake.nixosModules.options =
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
