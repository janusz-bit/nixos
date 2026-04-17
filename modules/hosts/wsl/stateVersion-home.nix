_: {
  flake.nixosModules."wsl/stateVersion-home" = _: {
    home-manager.users.nixos.home.stateVersion = "25.05";
  };
}
