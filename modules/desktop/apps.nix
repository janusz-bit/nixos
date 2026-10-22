# Aplikacje graficzne stacji roboczej (biuro, multimedia, komunikatory,
# grafika, notatki), Flatpak, AppImage, Mullvad VPN, Syncthing i reguły udev
# klawiatury Wooting.
_: {
  flake.modules.nixos.desktop-apps =
    { config, pkgs, ... }:
    let
      user = config.customBot.defaultUser;
      inherit (config.users.users.${user}) home;
    in
    {
      environment.systemPackages = with pkgs; [
        kdePackages.partitionmanager
        qbittorrent-enhanced
        vesktop
        vlc
        alacritty
        libreoffice-qt
        kdePackages.qrca
        # Dynamiczne tapety (także Wallpaper Engine); pakiety lokalne (local-packages).
        waywallen
        waywallen-kde-plugin
        signal-desktop
        element-desktop
        kdePackages.kcalc
        # gpg-agent dla Kleopatry włącza base-ssh (programs.gnupg.agent).
        kdePackages.kleopatra
        kdePackages.krecorder
        kdePackages.kolourpaint
        pinta
        nextcloud-client
        haruna
        kdePackages.elisa
        joplin-desktop
        trilium-desktop
        foliate
        kdePackages.kdenlive
        losange
        freecad-qt6
      ];

      services = {
        flatpak.enable = true;

        # Moduł daje demona (pkgs.mullvad); GUI (pkgs.mullvad-vpn) tylko z gui.enable.
        mullvad-vpn = {
          enable = true;
          gui.enable = true;
        };

        syncthing = {
          enable = true;
          inherit user;
          dataDir = "${home}/Sync";
          configDir = "${home}/.config/syncthing";
          openDefaultPorts = true;
        };
      };

      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      hardware.wooting.enable = true;
    };
}
