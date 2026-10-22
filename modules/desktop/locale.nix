# Polski układ i język: strefa czasowa, locale, klawiatura w konsoli i w
# sesji graficznej (xkb czyta też KWin na Waylandzie).
{ customTop, ... }:
{
  flake.modules.nixos.desktop-locale = _: {
    time.timeZone = customTop.locale.timeZone;
    i18n.defaultLocale = customTop.locale.language;
    console.keyMap = customTop.locale.keyMap;
    services.xserver.xkb.layout = customTop.locale.xkbLayout;
  };
}
