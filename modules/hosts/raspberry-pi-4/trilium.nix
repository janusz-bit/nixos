_: {
  flake.modules.nixos.trilium = _: {
    services.trilium-server = {
      enable = true;
      port = 8081;
    };
  };
}
