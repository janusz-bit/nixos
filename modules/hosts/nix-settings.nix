{ self, inputs, ... }:
{
  flake.nixosModules.nix-settings =
    { ... }:
    {
      nix.gc.automatic = true;
      nix.gc.dates = "2day";

    };

}
