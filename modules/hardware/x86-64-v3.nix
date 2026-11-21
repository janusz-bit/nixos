# Cechy systemowe gccarch-x86-64{,-v2,-v3} demona nix dla procesorów z AVX2:
# pozwalają budować lokalnie derywacje skompilowane pod x86-64-v3.
#
# nixpkgs daje derywacjom z gcc.arch platformy (np. pkgsx86_64_v3 z Chaotic-Nyx)
# requiredSystemFeatures = gccarch-<arch>, a bez tej cechy nix odmawia ich
# budowania. NixOS dodaje ją sam przy nixpkgs.hostPlatform.gcc.arch, które na
# laptopie ustawia nixpkgs-v3 (hosts/nixos); ten moduł zostaje dla hostów v3
# bez niego (kernel CachyOS v3, Proton-CachyOS v3 budowane lokalnie).
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
