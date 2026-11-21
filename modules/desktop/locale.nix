# Układ, język i położenie z customTop.locale (modules/args.nix): strefa
# czasowa, locale, klawiatura w konsoli i w sesji graficznej (xkb czyta też
# KWin na Waylandzie), domena regulacyjna Wi-Fi i stała lokalizacja GeoClue
# zamiast skanowania Wi-Fi.
#
# Sprawdzenie: `iw reg get` daje country PL (nie 00), `iw event -t` przez
# 10 min nie pokazuje skanów, a `busctl --system get-property
# org.freedesktop.GeoClue2 /org/freedesktop/GeoClue2/Manager
# org.freedesktop.GeoClue2.Manager AvailableAccuracyLevel` daje 8 (EXACT ze
# źródła stałego).
_: {
  flake.modules.nixos.desktop-locale =
    { config, ... }:
    {
      time.timeZone = config.customTop.locale.timeZone;
      i18n.defaultLocale = config.customTop.locale.defaultLocale;
      console.keyMap = config.customTop.locale.keyMap;
      services.xserver.xkb.layout = config.customTop.locale.xkbLayout;

      # Karta bez kraju w efuse (RTL8852BE laptopa: rtw89 „worldwide roaming
      # chip, follow the setting of stack”) zostaje bez tego przy domenie 00:
      # 5 GHz tylko pasywnie (dłuższe skany, brak sond) i tablice mocy WW
      # rtw89 zamiast ETSI.
      boot.kernelParams = [ "cfg80211.ieee80211_regdom=${config.customTop.locale.wifiRegdom}" ];

      location = { inherit (config.customTop.locale) latitude longitude; };

      # GeoClue włącza plasma6, a jego klientem jest knighttimed (Night Light
      # i motyw dzień/noc według słońca). Źródło Wi-Fi zleca wpa_supplicant
      # skan wszystkich kanałów co 300 s, a przy dokładności STREET co 10 s
      # (gclue-wifi.c); na laptopie każdy skan to ~5 s pingu 40–130 ms do
      # routera i zgubione pakiety, a listę okolicznych BSSID dostaje beacondb.
      # enableStatic wyłącza wszystkie pozostałe źródła (moduł geoclue2);
      # do godzin wschodu i zachodu wystarczy środek kraju.
      services.geoclue2 = {
        enableStatic = true;
        staticAltitude = 0;
        staticAccuracy = 300000;
      };
    };
}
