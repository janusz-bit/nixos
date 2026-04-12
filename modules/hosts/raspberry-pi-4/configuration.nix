{ ... }:
{
  flake.nixosModules.raspberry-pi-4-configuration =
    { pkgs, ... }:
    {
      services.displayManager = {
        sddm.wayland.enable = true;
        sddm.enable = true;
      };
      services.desktopManager.plasma6.enable = true;
    };
}
