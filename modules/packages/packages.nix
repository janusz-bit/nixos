{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.proton-cachyos-v3 = (
        pkgs.callPackage ./modules/packages/proton-bin {
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
    };
}
