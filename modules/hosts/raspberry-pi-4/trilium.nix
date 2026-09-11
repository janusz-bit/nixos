_: {
  flake.modules.nixos.trilium = _: {
    services.trilium-server = {
      enable = true;
      port = 8081;
      # installPhase z nixpkgs uzywa juz `rm -f .../linuxmusl-*.node`
      # (delete-if-present), wiec lokalne overrideAttrs jest zbedne.
      # Bylo potrzebne tylko dla nixpkgs z bezwarunkowym `rm` -
      # patrz temporary-fixes.md (pozycja zamknieta).
    };
  };
}
