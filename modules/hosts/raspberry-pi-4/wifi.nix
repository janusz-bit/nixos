{ customTop, ... }:
{
  flake.modules.nixos.rpi-wifi =
    { config, lib, ... }:
    let
      # SSID i hasło: modules/_secrets/wifi.age (agenix -e), plik env:
      #   WIFI_SSID='nazwa sieci'
      #   WIFI_PSK='hasło'
      # Dopóki pliku nie ma (albo nie jest w gicie — flake widzi tylko
      # śledzone pliki), profil nie powstaje, a ewaluacja tylko ostrzega.
      secretFile = customTop.secretsDir + "/wifi.age";
      hasSecret = builtins.pathExists secretFile;
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!hasSecret) [
          "rpi-wifi: brak modules/_secrets/wifi.age w gicie — Wi-Fi nie zostanie skonfigurowane."
        ];

        # Domena regulacyjna PL (jak raspi-config w Raspberry Pi OS). Bez niej
        # cfg80211 zostaje w domenie światowej "00": kanały 12–13 (2,4 GHz)
        # są tylko pasywne, więc router na takim kanale byłby nieosiągalny.
        boot.kernelParams = [ "cfg80211.ieee80211_regdom=PL" ];
      }
      (lib.mkIf hasSecret {
        # NetworkManager-ensure-profiles działa jako root i czyta plik przez
        # EnvironmentFile — wystarcza domyślne root:root 0400.
        age.secrets.wifi.file = secretFile;

        # Profil ląduje w /run/NetworkManager/system-connections (envsubst
        # podstawia $WIFI_SSID/$WIFI_PSK dopiero w runtime, poza store).
        # Przy kablu i Wi-Fi naraz trasa domyślna idzie przez Ethernet
        # (metryka 100 < 600).
        networking.networkmanager.ensureProfiles = {
          environmentFiles = [ config.age.secrets.wifi.path ];
          profiles.home-wifi = {
            connection = {
              id = "home-wifi";
              type = "wifi";
              autoconnect = true;
              # Serwer headless: ponawiaj bez końca zamiast blokować profil
              # na 5 min po 4 nieudanych próbach (np. po restarcie routera).
              autoconnect-retries = 0;
            };
            wifi = {
              mode = "infrastructure";
              ssid = "$WIFI_SSID";
              # 2 = wyłączone. Oszczędzanie energii brcmfmac na RPi daje
              # skoki opóźnień i zrywa połączenia (tunel, SSH).
              powersave = 2;
            };
            wifi-security = {
              key-mgmt = "wpa-psk"; # WPA2 oraz tryb mieszany WPA2/WPA3
              psk = "$WIFI_PSK";
            };
            ipv4.method = "auto";
            ipv6.method = "auto";
          };
        };

        # Zmiana treści wifi.age nie zmienia ścieżki /run/agenix/wifi, więc
        # bez tego nowe hasło weszłoby dopiero po restarcie.
        systemd.services.NetworkManager-ensure-profiles.restartTriggers = [ secretFile ];
      })
    ];
}
