{ self, ... }:
{
  # Dodaje własny pakiet prime-agent (modules/packages/_prime-agent)
  # do pkgs. Podpięty do hostów nixos i raspberry-pi-4.
  flake.overlays.prime-agent = _final: prev: {
    prime-agent = self.packages.${prev.stdenv.hostPlatform.system}.prime-agent;
  };
}
