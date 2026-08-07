{ self, inputs, ... }:
{
  flake.modules.nixos.options =
    { lib, ... }:
    {
      options.customBot = {
        flakeTarget = lib.mkOption {
          type = lib.types.str;
          default = "default";
        };
        enableFastfetch = lib.mkOption {
          type = lib.types.bool;
          default = true;
        };
        defaultUser = lib.mkOption {
          type = lib.types.str;
          default = "nixos";
        };
      };
    };
}
