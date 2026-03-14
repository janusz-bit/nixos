{ ... }:
{
  flake.nixosModules.nixos-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        zed-editor-fhs
        gparted
        qbittorrent-enhanced
      ];
      # Install firefox.
      programs.firefox.enable = true;
      hardware.wooting.enable = true;
      services.mullvad-vpn.enable = true;
      services.mullvad-vpn.package = pkgs.mullvad-vpn;

    };
}
