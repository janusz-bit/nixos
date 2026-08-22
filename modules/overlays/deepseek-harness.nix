{ self, ... }:
{
  # Dodaje własny pakiet deepseek-harness (modules/packages/_deepseek-harness)
  # do pkgs. Podpięty do hostów nixos i raspberry-pi-4.
  flake.overlays.deepseek-harness = _final: prev: {
    deepseek-harness = self.packages.${prev.stdenv.hostPlatform.system}.deepseek-harness;
  };
}
