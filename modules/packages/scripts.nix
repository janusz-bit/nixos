{
  perSystem =
    { pkgs, ... }:
    {
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
        latest_num="''${latest_tag#v}"
        if [[ "$latest_num" == *.*.* ]]; then
          IFS='.' read -r major minor patch <<< "$latest_num"
          new_tag="v''${major}.''${minor}.$((patch + 1))"
        elif [[ "$latest_num" == *.* ]]; then
          IFS='.' read -r major minor <<< "$latest_num"
          new_tag="v''${major}.$((minor + 1))"
        else
          new_tag="v$((latest_num + 1))"
        fi
        echo "Releasing $new_tag..."
        git commit -a -m "Release $new_tag" || true
        git tag $new_tag
        git push
        git push --tags
        echo "Release $new_tag pushed successfully!"
      '';
    };
}
