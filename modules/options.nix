# Centralized top-level options for the entire flake. Every module reads global
# state through `config.customBot.*` rather than via `_module.args`.
{ ... }:
{
  flake.modules.nixos.options =
    { lib, ... }:
    {
      options.customBot.flakeTarget = lib.mkOption {
        type = lib.types.str;
        default = "default";
        description = ''
          Logical name of the host this configuration is built for.
          Used by `update` / `update-boot` shell aliases to build the right target
          and to push the correct closure to Cachix.
        '';
        example = "nixos";
      };

      options.customBot.enableFastfetch = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Display fastfetch in the fish greeting on this host.";
      };

      options.customBot.defaultUser = lib.mkOption {
        type = lib.types.str;
        default = "nixos";
        description = "Unix account created on first boot of this host.";
        example = "dinosaur";
      };
    };
}
