# IMPORTANT: changes have to be written to config.txt directly
# sudo mount /dev/disk/by-label/FIRMWARE /mnt
# sudo micro /mnt/config.txt # &lt;-- make changes here
# dtparam=audio=on
{
  inputs,
  self,
  lib,
  ...
}:
{
  flake.nixosConfigurations.raspberry-pi-4 = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    modules = [
      self.nixosModules.base
      self.nixosModules.raspberry-pi-4
      inputs.nixos-hardware.nixosModules.raspberry-pi-4
      (_: {
        custom.flakeTarget = "raspberry-pi-4";
        custom.defaultUser = "nixos";
      })
    ];
  };
}
