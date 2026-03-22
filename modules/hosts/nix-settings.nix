{ self, inputs, ... }:
{
  flake.nixosModules.nix-settings =
    { ... }:
    {
      nix.gc.automatic = true;
      nix.gc.dates = "2day";
      nix.gc.options = "--delete-older-than 7d";
      nix.settings.auto-optimise-store = true;

    };

}
