# Sesja graficzna: Plasma 6 na Waylandzie z SDDM. Serwer X nie jest
# potrzebny — XWayland uruchamia KWin, a opcje xkb (desktop/locale.nix)
# działają bez services.xserver.enable. KWallet przez PAM (login, sddm, kde)
# konfiguruje moduł plasma6.
# Sprawdzenie: `loginctl show-session $XDG_SESSION_ID -p Type` → wayland.
_: {
  flake.modules.nixos.desktop-plasma = _: {
    services = {
      displayManager = {
        sddm = {
          wayland.enable = true;
          enable = true;
          autoNumlock = true;
        };
      };
      desktopManager.plasma6.enable = true;
    };

    # plasma6 włącza programs.kde-pim (mkDefault), a od nixpkgs 55bfb4d
    # kmail/kontact/merkuro domyślnie idą za kde-pim.enable i dociągają cały
    # pakiet PIM (KMail, KOrganizer, Akregator, KAddressBook, Merkuro;
    # ~110 MiB). Zostaje tylko baza modułu (akonadi, kdepim-runtime,
    # akonadi-import-wizard).
    programs.kde-pim = {
      kmail = false;
      kontact = false;
      merkuro = false;
    };

    # baloo_file_extractor jest QGuiApplication, więc abortuje przy starcie bez
    # działającego WAYLAND_DISPLAY/DISPLAY. kde-baloo.service startuje, zanim
    # startplasma zaimportuje te zmienne do systemd --user, a baloo_file
    # przekazuje potomkom własne środowisko (KDE bug 524392). Indeksowanie jest
    # bezgłowe, więc offscreen usuwa zależność od sesji; KIdleTime nie widzi
    # wtedy aktywności i Baloo indeksuje wolniej. Usunąć po naprawie upstreamu
    # (baloo MR 331) — temporary-fixes.md.
    systemd.user.services.kde-baloo = {
      overrideStrategy = "asDropin";
      environment.QT_QPA_PLATFORM = "offscreen";
    };

    # Num Lock włączony w sesji Plasmy (0 = włącz). KDE czyta domyślne
    # konfiguracje z XDG_CONFIG_DIRS, czyli /etc/xdg — nie z /etc.
    environment.etc."xdg/kcminputrc".text = ''
      [Keyboard]
      NumLock=0
    '';
  };
}
