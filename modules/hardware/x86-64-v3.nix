_: {
  flake.modules.nixos.hardware-x86-64-v3 = _: {
    nix.settings.extra-system-features = [
      "gccarch-x86-64-v3"
      "gccarch-x86-64-v2"
      "gccarch-x86-64"
    ];
  };
}
