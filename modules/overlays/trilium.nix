{ inputs, ... }:
{
  flake.overlays.trilium = final: prev: {
    trilium-server = inputs.trilium.packages.${final.stdenv.hostPlatform.system}.server;
    trilium-desktop = inputs.trilium.packages.${final.stdenv.hostPlatform.system}.desktop;
  };
}
