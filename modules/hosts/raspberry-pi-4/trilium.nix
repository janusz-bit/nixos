{ ... }:
{
  flake.modules.nixos.trilium =
    {
      ...
    }:
    {
      services.trilium-server = {
        enable = true;
        port = 8081;
      };
    };
}
