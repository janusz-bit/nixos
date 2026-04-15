{ inputs, ... }:
{
  flake.overlays.bootdev-cli-overlay = final: prev: {
    bootdev-cli = inputs.self.packages.${final.stdenv.hostPlatform.system}.bootdev-cli;
  };
}
