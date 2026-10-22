# Cechy systemowe gccarch-x86-64{,-v2,-v3} demona nix dla procesorów z AVX2:
# pozwalają budować lokalnie derywacje skompilowane pod x86-64-v3.
#
# nixpkgs daje derywacjom z gcc.arch platformy (np. pkgsx86_64_v3 z Chaotic-Nyx)
# requiredSystemFeatures = gccarch-<arch>, a bez tej cechy nix odmawia ich
# budowania. NixOS dodaje ją sam tylko przy nixpkgs.hostPlatform.gcc.arch,
# a tego celowo nie ma: userspace pod v3 nie jest w cache.nixos.org
# i budowałby się lokalnie.
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
