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

      packages.update-flake = pkgs.writeShellScriptBin "flake-update" ''
        set -e
        echo "Updating flake inputs..."
        nix flake update
        if ! git diff --exit-code flake.lock > /dev/null; then
          echo "Committing flake.lock..."
          git add flake.lock
          git commit -m "Update flake.lock" flake.lock
        fi
        echo "Updating bootdev-cli..."
        ${pkgs.lib.getExe pkgs.nix-update} --commit -F bootdev-cli
        echo "Updating proton-cachyos-v3..."
        ${pkgs.lib.getExe pkgs.nix-update} -F proton-cachyos-v3 -u
        echo "All packages updated!"
      '';

      packages.flake-release = pkgs.writeShellScriptBin "flake-release" ''
        set -e
        latest_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "v0")
        new_tag="v$(( ''${latest_tag#v} + 1 ))"
        echo "Releasing $new_tag..."
        git commit -a -m "Release $new_tag" || true
        git tag $new_tag
        git push
        git push --tags
        echo "Release $new_tag pushed successfully!"
      '';

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
