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

    # Num Lock włączony w sesji Plasmy (0 = włącz). KDE czyta domyślne
    # konfiguracje z XDG_CONFIG_DIRS, czyli /etc/xdg — nie z /etc.
    environment.etc."xdg/kcminputrc".text = ''
      [Keyboard]
      NumLock=0
    '';
  };
}
