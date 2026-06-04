{ inputs, ... }:
{
  flake.modules.nixos.rpi-sdImage = {
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
