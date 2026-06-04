{ self, inputs, ... }:
{
  flake.modules.nixos.nix-settings =
    { ... }:
    {
      nix.gc.automatic = true;
      nix.gc.dates = "weekly";
      nix.gc.options = "--delete-older-than 7d";
      nix.settings.auto-optimise-store = true;

      nix.settings.trusted-users = [ "@wheel" ];

    };

}
