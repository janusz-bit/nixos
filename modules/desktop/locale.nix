# Układ i język z customTop.locale (modules/args.nix): strefa czasowa, locale,
# klawiatura w konsoli i w sesji graficznej (xkb czyta też KWin na Waylandzie).
_: {
  flake.modules.nixos.desktop-locale =
    { config, ... }:
    {
      time.timeZone = config.customTop.locale.timeZone;
      i18n.defaultLocale = config.customTop.locale.defaultLocale;
      console.keyMap = config.customTop.locale.keyMap;
      services.xserver.xkb.layout = config.customTop.locale.xkbLayout;
    };
}
