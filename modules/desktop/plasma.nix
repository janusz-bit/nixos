# Sesja graficzna: Plasma 6 na Waylandzie z SDDM, bez serwera X (XWayland
# uruchamia KWin, a xkb z desktop/locale.nix działa bez services.xserver.enable).
# KWallet przez PAM konfiguruje moduł plasma6.
# Sprawdzenie: `loginctl show-session $XDG_SESSION_ID -p Type` → wayland.
_: {
  flake.modules.nixos.desktop-plasma = _: {
    services = {
      displayManager.sddm = {
        enable = true;
        wayland.enable = true;
        autoNumlock = true;
      };
      desktopManager.plasma6.enable = true;
    };

    # plasma6 włącza programs.kde-pim, a kmail/kontact/merkuro idą za nim i
    # dociągają cały PIM (~110 MiB); zostaje baza (akonadi, kdepim-runtime).
    programs.kde-pim = {
      kmail = false;
      kontact = false;
      merkuro = false;
    };

    # Tymczasowe (temporary-fixes.md nr 8, KDE bug 524392): kde-baloo startuje przed
    # importem WAYLAND_DISPLAY/DISPLAY i ekstraktor (QGuiApplication) abortuje;
    # offscreen nie potrzebuje ekranu (KIdleTime nie widzi aktywności, indeksuje wolniej).
    systemd.user.services.kde-baloo = {
      overrideStrategy = "asDropin";
      environment.QT_QPA_PLATFORM = "offscreen";
    };

    # Num Lock w sesji Plasmy (0 = włącz); domyślne KDE czyta z /etc/xdg, nie z /etc.
    environment.etc."xdg/kcminputrc".text = ''
      [Keyboard]
      NumLock=0
    '';
  };
}
