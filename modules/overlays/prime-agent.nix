{ self, ... }:
{
  # Dodaje własny pakiet prime-agent (modules/packages/_prime-agent)
  # do pkgs. Podpięty do hosta nixos (modules/hosts/nixos/configuration.nix).
  flake.overlays.prime-agent = _final: prev: {
    prime-agent = self.packages.${prev.stdenv.hostPlatform.system}.prime-agent;
  };
}
