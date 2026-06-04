{
  inputs,
  self,
  config,
  ...
}:
{
  flake.packages.x86_64-linux.proton-cachyos-v3 =
    inputs.nixpkgs.legacyPackages.x86_64-linux.callPackage ./_proton-bin
      {
        toolTitle = "Proton-CachyOS x86-64-v3";
        tarballPrefix = "proton-";
        tarballSuffix = "-x86_64_v3.tar.xz";
        toolPattern = "proton-cachyos-.*";
        releasePrefix = "cachyos-";
        releaseSuffix = "-slr";
        versionFilename = "cachyos-v3-version.json";
        owner = "CachyOS";
        repo = "proton-cachyos";
      };

  perSystem =
    { pkgs, ... }:
    {
      packages.bootdev-cli = pkgs.bootdev-cli.overrideAttrs (oldAttrs: rec {
        version = "1.29.5";

        src = pkgs.fetchFromGitHub {
          owner = "bootdotdev";
          repo = "bootdev";
          rev = "v${version}";
          hash = "sha256-nfgmlKIXtQqiharS1ezES5dFa6IE7Q2TvIhh/qiIB2Q=";
        };

        vendorHash = "sha256-ZDioEU5uPCkd+kC83cLlpgzyOsnpj2S7N+lQgsQb8uY=";
      });

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
