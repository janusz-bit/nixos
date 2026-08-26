{
  inputs,
  self,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    {
      packages = {
        bootdev-cli = pkgs.callPackage ./_bootdev-cli { };
        deepseek-harness = pkgs.callPackage ./_deepseek-harness { };

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
