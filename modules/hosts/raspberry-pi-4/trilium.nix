{ self, customTop, ... }:
{
  flake.nixosModules."raspberry-pi-4/trilium" =
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
