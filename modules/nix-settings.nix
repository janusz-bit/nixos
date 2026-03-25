{ self, inputs, ... }:
{
  flake.nixosModules.nix-settings =
    { ... }:
    {
      nix.gc.automatic = true;
      nix.gc.dates = "2day";
      nix.gc.options = "--delete-older-than 7d";
      nix.settings.auto-optimise-store = true;

      nix.settings.substituters = [ "https://attic.xuyh0120.win/lantian" ];
      nix.settings.trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];

    };

}
