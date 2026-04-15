{ self, inputs, ... }:
{
  flake.nixosModules.nix-settings =
    { ... }:
    {
      nix.gc.automatic = true;
      nix.gc.dates = "weekly";
      nix.gc.options = "--delete-older-than 7d";
      nix.settings.auto-optimise-store = true;

      nix.settings.substituters = [
        # "https://attic.xuyh0120.win/lantian"
        "https://janusz-bit.cachix.org"
      ];
      nix.settings.trusted-public-keys = [
        # "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
        "janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo="
      ];

      nix.settings.trusted-users = [ "@wheel" ];

    };

}
