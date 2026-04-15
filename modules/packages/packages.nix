{ inputs, ... }:
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
        version = "1.28.0";

        src = pkgs.fetchFromGitHub {
          owner = "bootdotdev";
          repo = "bootdev";
          rev = "v${version}";
          hash = "sha256-sBPId1wEsIG1E+sf+pbqfz0xW0+PHVAoRYTkFLXpWOU=";
        };

        vendorHash = "sha256-ZDioEU5uPCkd+kC83cLlpgzyOsnpj2S7N+lQgsQb8uY=";
      });

      packages.update-flake = pkgs.writeShellScriptBin "update-flake" ''
        set -e
        echo "Updating flake inputs..."
        nix flake update
        if ! git diff --exit-code flake.lock > /dev/null; then
          echo "Committing flake.lock..."
          git add flake.lock
          git commit -m "Update flake.lock" flake.lock
        fi
        echo "Updating bootdev-cli..."
        nix run nixpkgs#nix-update -- --commit -F bootdev-cli
        echo "Updating proton-cachyos-v3..."
        nix run nixpkgs#nix-update -- -F proton-cachyos-v3 -u
        echo "All packages updated!"
      '';
    };
}
