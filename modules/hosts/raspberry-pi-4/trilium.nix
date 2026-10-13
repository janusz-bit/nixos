_: {
  flake.modules.nixos.rpi-trilium = _: {
    services.trilium-server = {
      enable = true;
      port = 8081;
    };
  };
}
