{ inputs, ... }:
{
  flake.modules.nixos.rpi-sd-image = {
    imports = [
      "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
      {
        sdImage = {
          expandOnBoot = true;
          compressImage = false;
        };
      }
    ];
  };
}
