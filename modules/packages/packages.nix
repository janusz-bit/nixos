{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      packages = {
        proton-cachyos-v3 = (
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
          }
        );
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        tdm-installer = pkgs.callPackage ./_tdm-installer { };
      };
    };
}
