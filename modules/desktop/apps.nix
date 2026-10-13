# Aplikacje graficzne stacji roboczej (biuro, multimedia, komunikatory,
# grafika, notatki) oraz usługi użytkownika: Mullvad VPN i Syncthing.
# Narzędzia programistyczne: desktop/dev.nix, przeglądarki:
# desktop/browsers.nix, agenty AI: desktop/ai.nix, gry: modules/gaming/.
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
        # Waywallen — dynamiczne tapety (zamiennik Wallpaper Engine Plugin).
        # Nie wymaga Steama/Protonu; tapety Wallpaper Engine przez wbudowany
        # plugin open-wallpaper-engine. Ustawianie tapet: aplikacja waywallen.
        # Pakiety lokalne z overlaya local-packages (modules/packages/packages.nix).
        waywallen
        waywallen-kde-plugin
        signal-desktop
        element-desktop
        kdePackages.kcalc
        # Kleopatra — GUI do kluczy OpenPGP/S/MIME. gpg-agent (z pinentry-qt
        # od plasma6) włącza już base-ssh (programs.gnupg.agent).
        kdePackages.kleopatra
        # KRecorder — dyktafon (nagrywanie dźwięku z mikrofonu, lista nagrań,
        # odtwarzacz; aplikacja KDE na Kirigami).
        kdePackages.krecorder
        # Narzędzia do rysowania (odpowiednik Windows Paint):
        # KolourPaint — prosty paint z KDE; Pinta — jak Paint.NET
        # (warstwy, historia zmian, efekty).
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

        # Mullvad split upstream: pkgs.mullvad = daemon (module default),
        # pkgs.mullvad-vpn = GUI only, enabled via gui.enable.
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

      # AppImage uruchamiane wprost (binfmt) przez appimage-run.
      programs.appimage = {
        enable = true;
        binfmt = true;
      };

      # Klawiatura Wooting: reguły udev dla Wootility.
      hardware.wooting.enable = true;
    };
}
