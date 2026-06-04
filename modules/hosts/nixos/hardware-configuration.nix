_: {
  flake.modules.nixos.nixos-hardware-configuration =
    import ./_hardware-configuration/hardware-configuration.nix;

}
