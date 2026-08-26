{ inputs, ... }:
{
  # Dodaje pakiet prime-agent z numtide/llm-agents.nix do pkgs.
  # Podpięty do hostów nixos i raspberry-pi-4.
  flake.overlays.prime-agent = _final: prev: {
    prime-agent = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.prime-agent;
  };
}
