_: {
  flake.nixosModules."raspberry-pi-4/hardware-configuration" =
    import ./_hardware-configuration/hardware-configuration.nix;

}
