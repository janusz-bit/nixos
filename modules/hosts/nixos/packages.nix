{ self, ... }:
{
  flake.nixosModules.nixos-packages =
    { pkgs, ... }:
    {
      environment.systemPackages = with pkgs; [
        zed-editor
        gparted
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
        self.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
        noctalia-shell
        niri
        alacritty
        sqlite
        brave
        libreoffice-qt
        kdePackages.qrca
        signal-desktop
        element-desktop
        prismlauncher
      ];
      # Install firefox.
      programs.firefox.enable = true;
      hardware.wooting.enable = true;
      services.mullvad-vpn.enable = true;
      services.mullvad-vpn.package = pkgs.mullvad-vpn;
      programs.steam = {
        enable = true;
        remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
        dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server hosting};
        extraCompatPackages = [
          self.packages.${pkgs.stdenv.hostPlatform.system}.proton-cachyos-v3
        ];
      };
      programs.gamemode.enable = true; # for performance mode
      services.syncthing = {
        enable = true;
        user = "dinosaur";
        dataDir = "/home/dinosaur/Sync";
        configDir = "/home/dinosaur/.config/syncthing";
      };
    };
}
