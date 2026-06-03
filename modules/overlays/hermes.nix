{ inputs, ... }:
{
  flake.overlays.hermes = final: prev: {
    hermes-full = inputs.hermes-agent.packages.${final.stdenv.hostPlatform.system}.full;
  };
}
