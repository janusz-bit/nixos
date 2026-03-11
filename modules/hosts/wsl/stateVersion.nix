{ ... }:
{
  flake.nixosModules.wsl-stateVersion =
    { ... }:
    {
      system.stateVersion = "25.05";
    };
}
