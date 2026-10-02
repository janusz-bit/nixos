{
  inputs,
  self,
  ...
}:
let
  # Pakiety lokalne — jedno źródło dla hostów (overlay) i dla
  # `packages.<system>` (nix build / nix-update w flake-update).
  # bootdev-cli nadpisuje wersję z nixpkgs: lokalna jest aktualizowana
  # przez flake-update i bywa nowsza.
  localPackages = pkgs: {
    bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
    waywallen = pkgs.callPackage ./_waywallen { };
    waywallen-kde-plugin = pkgs.callPackage ./_waywallen-kde-plugin { };
  };
in
{
  flake.overlays.local-packages = final: _prev: localPackages final;

  perSystem =
    { pkgs, ... }:
    {
      packages = localPackages pkgs // {
        raspberry-pi-4-sd-image =
          let
            image = inputs.nixpkgs.lib.nixosSystem {
              modules = [
                { nixpkgs.hostPlatform = "aarch64-linux"; }
                self.modules.nixos.raspberry-pi-4
                self.modules.nixos.rpi-sdImage
              ];
            };
          in
          image.config.system.build.sdImage;
      };
    };
}
