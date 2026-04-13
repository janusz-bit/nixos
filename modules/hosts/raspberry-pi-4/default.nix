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
    modules = [
      { nixpkgs.hostPlatform = "aarch64-linux"; }
      self.nixosModules.raspberry-pi-4
    ];
  };
}
