_: {
  flake.modules.nixos.build-flags-x86-64-v3 = _: {
    nix.settings.extra-system-features = [
      "gccarch-x86-64-v3"
      "gccarch-x86-64-v2"
      "gccarch-x86-64"
    ];

    # Odkomentuj poniższy blok, aby wymusić rekompilację CAŁEGO systemu pod architekturę x86-64-v3:
    # nixpkgs.hostPlatform = {
    #   gcc.arch = "x86-64-v3";
    #   gcc.tune = "x86-64-v3";
    #   system = "x86_64-linux";
    # };
  };
}
