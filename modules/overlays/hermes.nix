{ inputs, ... }:
{
  flake.overlays.hermes = final: prev: {
    hermes-full =
      (builtins.getFlake "github:NousResearch/hermes-agent")
      .packages.${final.stdenv.hostPlatform.system}.full;
  };
}
