{ self, inputs, ... }:
{
  flake.modules.nixos.nix-settings = _: {
    nix = {
      gc = {
        automatic = true;
        dates = "weekly";
        options = "--delete-older-than 7d";
      };
      settings = {
        auto-optimise-store = true;
        trusted-users = [ "@wheel" ];
      };
    };
  };

}
