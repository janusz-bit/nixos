{ inputs, ... }:
{
  flake.overlays.bootdev-cli-overlay = final: prev: {
    bootdev-cli = inputs.self.packages.${final.system}.bootdev-cli;
  };
}
