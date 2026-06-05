{ self, ... }:
{
  flake.modules.nixos.trilium =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      services.trilium-server = {
        enable = true;
        port = 8081;
      };
    };
}
