{ self, ... }:
{
  # Dodaje własne pakiety prime-agent + prime-agent-bridge
  # (modules/packages/_prime-agent*) do pkgs. Podpięte do hostów nixos
  # i raspberry-pi-4.
  flake.overlays.prime-agent = _final: prev: {
    prime-agent = self.packages.${prev.stdenv.hostPlatform.system}.prime-agent;
    prime-agent-bridge = self.packages.${prev.stdenv.hostPlatform.system}.prime-agent-bridge;
  };
}
