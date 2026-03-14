{ ... }:
{
  flake.nixosModules.nixos-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        zed-editor-fhs
        gparted
      ];
      # Install firefox.
      programs.firefox.enable = true;
      hardware.wooting.enable = true;
    };
}
