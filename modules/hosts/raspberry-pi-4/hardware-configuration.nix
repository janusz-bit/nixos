_: {
  flake.modules.nixos.rpi-hardware-configuration =
    import ./_hardware-configuration/hardware-configuration.nix;

}
