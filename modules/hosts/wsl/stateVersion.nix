{ ... }:
{
  flake.nixosModules.wsl-stateVersion =
    { ... }:
    {
      system.stateVersion = "25.05";
      home-manager.users.nixos.home.stateVersion = "25.05";
    };
}
