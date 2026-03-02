{ ... }:
{
  flake.nixosModules.wsl-stateVersion =
    { ... }:
    {
      home-manager.users.nixos.home.stateVersion = "25.05";
      system.stateVersion = "25.05";
    };
}
