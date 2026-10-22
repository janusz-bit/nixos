# Sieć RPi: NetworkManager z kablem i zapasowym Wi-Fi (profil home-wifi
# z sekretu wifi.age, timer home-wifi-reconnect podnosi go, gdy NM go
# zablokuje), domena regulacyjna PL. Usługi WWW słuchają na localhost
# i wychodzą tylko tunelem (cloudflared.nix); firewall wpuszcza jedynie SSH
# z domowego LAN-u (base-ssh-lan).
#
# Sprawdzenie: `nmcli connection show`, `iw reg get`,
# `journalctl -u home-wifi-reconnect -b`.
{ customTop, ... }:
{
  flake.modules.nixos.rpi-network =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      wifiProfile = "home-wifi";
      # SSID i hasło: wifi.age (agenix -e), plik env: WIFI_SSID='…',
      # WIFI_PSK='…'. Bez pliku w gicie profil nie powstaje (ostrzeżenie).
      secretFile = customTop.secretsDir + "/wifi.age";
      hasSecret = builtins.pathExists secretFile;

      # Lista do zmiennej: przy pipefail wczesne wyjście `grep -q` mogłoby
      # zabić nmcli SIGPIPE-em i zerwać aktywne Wi-Fi.
      reconnect = pkgs.writeShellApplication {
        name = "home-wifi-reconnect";
        runtimeInputs = [
          config.networking.networkmanager.package
          pkgs.gnugrep
        ];
        text = ''
          active="$(nmcli -g NAME connection show --active)"
          if ! grep -qxF ${lib.escapeShellArg wifiProfile} <<<"$active"; then
            nmcli connection up ${lib.escapeShellArg wifiProfile}
          fi
        '';
      };
    in
    lib.mkMerge [
      {
        networking.networkmanager.enable = true;

        # Vhosty nginx bez własnego `listen` (Nextcloud z /.well-known Matrixa)
        # słuchają tylko na localhost, skąd bierze je tunel (cloudflared →
        # localhost:80); domyślne 0.0.0.0:80 chroniłby jedynie firewall.
        services.nginx = {
          defaultListenAddresses = [
            "127.0.0.1"
            "[::1]"
          ];
          recommendedProxySettings = true;
          recommendedGzipSettings = true;
        };

        warnings = lib.optionals (!hasSecret) [
          "rpi-network: brak modules/_secrets/wifi.age w gicie — Wi-Fi nie zostanie skonfigurowane."
        ];

        # Domena regulacyjna PL (jak raspi-config w Raspberry Pi OS). Bez niej
        # cfg80211 zostaje w domenie światowej "00": kanały 12–13 (2,4 GHz)
        # są tylko pasywne, więc router na takim kanale byłby nieosiągalny.
        boot.kernelParams = [ "cfg80211.ieee80211_regdom=${customTop.locale.wifiRegdom}" ];
      }
      (lib.mkIf hasSecret {
        # NetworkManager-ensure-profiles działa jako root i czyta plik przez
        # EnvironmentFile — wystarcza domyślne root:root 0400.
        age.secrets.wifi.file = secretFile;

        # Profil w /run/NetworkManager/system-connections (envsubst podstawia
        # $WIFI_SSID/$WIFI_PSK w runtime, poza store). Przy kablu i Wi-Fi
        # naraz trasa domyślna idzie Ethernetem (metryka 100 < 600).
        networking.networkmanager.ensureProfiles = {
          environmentFiles = [ config.age.secrets.wifi.path ];
          profiles.${wifiProfile} = {
            connection = {
              id = wifiProfile;
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

        systemd = {
          # Zmiana treści wifi.age nie zmienia ścieżki /run/agenix/wifi, więc
          # bez tego nowe hasło weszłoby dopiero po restarcie.
          services.NetworkManager-ensure-profiles.restartTriggers = [ secretFile ];

          # Gdy uwierzytelnienie się nie uda, a profil nie ma zapisanego
          # udanego połączenia (bywa tak zaraz po restarcie), NM prosi agenta
          # sekretów o nowe hasło. Serwer agenta nie ma (nm-file-secret-agent
          # z nixpkgs takie prośby odrzuca), więc aktywacja kończy się
          # "no secrets" i NM blokuje autoconnect profilu do restartu; tak samo
          # po wyczerpaniu connection.auth-retries (3 próby). autoconnect-retries
          # tej blokady nie obejmuje. Timer podnosi profil, jeśli nie jest
          # aktywny ani w trakcie łączenia. Root, bo polkit pozwala sterować
          # połączeniami NM tylko jemu i sesjom lokalnym.
          services.home-wifi-reconnect = {
            description = "Reactivate the home-wifi profile after NetworkManager blocked it";
            serviceConfig = {
              Type = "oneshot";
              ExecStart = lib.getExe reconnect;
              NoNewPrivileges = true;
              ProtectSystem = "strict";
              ProtectHome = true;
              PrivateTmp = true;
            };
          };
          timers.home-wifi-reconnect = {
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "5min";
              OnUnitActiveSec = "5min";
            };
          };
        };
      })
    ];
}
