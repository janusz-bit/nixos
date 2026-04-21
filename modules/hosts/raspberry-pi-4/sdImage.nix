{ inputs, ... }:
{
  flake.nixosModules."raspberry-pi-4/sdImage" = {
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
