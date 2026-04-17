_: {
  flake.nixosModules."nixos/hardware-configuration" =
    import ./_hardware-configuration/hardware-configuration.nix;

}
