{
  inputs,
  self,
  config,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
      packages.prime-agent = pkgs.callPackage ./_prime-agent { };

      packages.raspberry-pi-4-sd-image =
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
}
