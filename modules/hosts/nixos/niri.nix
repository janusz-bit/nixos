{ ... }:
{
  flake.nixosModules.nixos-niri =
    { pkgs, ... }:
    {
      programs.niri.enable = true;
      environment.systemPackages = with pkgs; [
        inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
        # ... maybe other stuff
      ];

    };
}
