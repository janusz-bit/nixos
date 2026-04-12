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
      self.nixosModules.raspberry-pi-4
    ];
  };
  flake.nixosConfigurations.raspberry-pi-4-cross = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      { nixpkgs.crossSystem.system = "aarch64-linux"; }
      self.nixosModules.raspberry-pi-4
    ];
  };
}
