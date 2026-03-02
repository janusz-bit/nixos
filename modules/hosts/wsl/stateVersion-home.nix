{ ... }:
{
  flake.nixosModules.wsl-stateVersion-home =
    { ... }:
    {
      home-manager.users.nixos.home.stateVersion = "25.05";
    };
}
