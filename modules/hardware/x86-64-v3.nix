# Cechy systemowe gccarch-x86-64{,-v2,-v3} demona nix dla procesorów z AVX2:
# pozwalają budować lokalnie derywacje skompilowane pod x86-64-v3.
#
# nixpkgs dodaje derywacjom z ustawionym gcc.arch platformy (np. zestaw
# pkgsx86_64_v3 z Chaotic-Nyx) requiredSystemFeatures = gccarch-<arch>, a bez
# tej cechy nix odmawia ich budowania. Moduł NixOS ustawia ją sam tylko
# wtedy, gdy nixpkgs.hostPlatform.gcc.arch jest ustawione, a tego celowo tu
# nie ma: całego userspace'u pod v3 nie ma w cache.nixos.org, budowałby się
# lokalnie.
#
# Sprawdzenie: `nix config show system-features` zawiera gccarch-x86-64-v3.
_: {
  flake.modules.nixos.hardware-x86-64-v3 = _: {
    nix.settings.extra-system-features = [
      "gccarch-x86-64-v3"
      "gccarch-x86-64-v2"
      "gccarch-x86-64"
    ];
  };
}
