_: {
  flake.modules.nixos.trilium =
    {
      pkgs,
      lib,
      ...
    }:
    {
      services.trilium-server = {
        enable = true;
        port = 8081;
        # nixpkgs bug (trilium-server 0.105.0): installPhase does an
        # unconditional `rm .../better-sqlite3/prebuilds/linuxmusl-x64.node`,
        # but 0.105.0 tarballs no longer ship that file (arm64 ships only
        # linuxmusl-arm64.node + linux-arm64.node) → build fails with
        # "No such file or directory". Replace with delete-if-present, which
        # still drops the musl prebuilds (the original rm's purpose: they are
        # for musl libc and would be wrongly auto-patched on glibc NixOS),
        # and works for both x86_64 and aarch64 tarballs.
        package = pkgs.trilium-server.overrideAttrs (_: {
          installPhase = ''
            runHook preInstall
            mkdir -p "$out/share/trilium-server"
            cp -r ./* "$out/share/trilium-server/"
            find "$out/share/trilium-server/node_modules/better-sqlite3/prebuilds" \
              -name 'linuxmusl-*.node' -delete 2>/dev/null || true
            makeWrapper "$out/share/trilium-server/node/bin/node" "$out/bin/trilium-server" \
              --chdir "$out/share/trilium-server" \
              --add-flags "main.cjs"
            runHook postInstall
          '';
        });
      };
    };
}
