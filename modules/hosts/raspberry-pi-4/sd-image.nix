# Obraz karty SD/dysku z pełnym systemem raspberry-pi-4 (agregat hosta bez
# _hardware-configuration.nix — system plików daje moduł sd-image). Służy do
# pierwszej instalacji; potem host aktualizuje się zwykłym `update`.
#
# Build: nix build .#raspberry-pi-4-sd-image (na laptopie przez emulację
# aarch64), zapis: dd na kartę/dysk; partycja rozszerza się przy 1. starcie.
{ inputs, self, ... }:
{
  flake.modules.nixos.rpi-sd-image = _: {
    imports = [ "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix" ];
    sdImage.compressImage = false;
  };

  perSystem = _: {
    packages.raspberry-pi-4-sd-image =
      (inputs.nixpkgs.lib.nixosSystem {
        modules = [
          # To, co hostom dokłada rejestr (registry.nix).
          {
            nixpkgs.hostPlatform = "aarch64-linux";
            networking.hostName = "raspberry-pi-4";
            customBot.flakeTarget = "raspberry-pi-4";
          }
          self.modules.nixos.raspberry-pi-4
          self.modules.nixos.rpi-sd-image
        ];
      }).config.system.build.sdImage;
  };
}
