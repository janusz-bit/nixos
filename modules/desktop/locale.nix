# Polski układ i język: strefa czasowa, locale, klawiatura w konsoli i w
# sesji graficznej (xkb czyta też KWin na Waylandzie).
_: {
  flake.modules.nixos.desktop-locale = _: {
    time.timeZone = "Europe/Warsaw";
    i18n.defaultLocale = "pl_PL.UTF-8";
    console.keyMap = "pl2";
    services.xserver.xkb = {
      layout = "pl";
      variant = "";
    };
  };
}
