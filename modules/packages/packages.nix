{ inputs, self, ... }:
{
  flake.packages.x86_64-linux.proton-cachyos-v3 =
    let
      pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
    in
    pkgs.callPackage ./_proton-bin {
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
        version = "1.29.4";

        src = pkgs.fetchFromGitHub {
          owner = "bootdotdev";
          repo = "bootdev";
          rev = "v${version}";
          hash = "sha256-BU43XyK+5/YTI+61UGZSUPHmeWUIlal7sW6vgR5KCPg=";
        };

        vendorHash = "sha256-ZDioEU5uPCkd+kC83cLlpgzyOsnpj2S7N+lQgsQb8uY=";
      });

      packages.raspberry-pi-4-sd-image =
        let
          image = inputs.nixpkgs.lib.nixosSystem {
            modules = [
              { nixpkgs.hostPlatform = "aarch64-linux"; }
              self.nixosModules."raspberry-pi-4"
              self.nixosModules."raspberry-pi-4/sdImage"
            ];
          };
        in
        image.config.system.build.sdImage;
    };
}
