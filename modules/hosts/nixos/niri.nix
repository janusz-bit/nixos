{ inputs, ... }:
{
  flake.modules.nixos.nixos-niri =
    { pkgs, ... }:
    {
      programs.niri.enable = true;
      environment.systemPackages = with pkgs; [
        # ... maybe other stuff
        alacritty
      ];

    };
}
