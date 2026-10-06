# Reguły agenix CLI (agenix -e / -r). Plik może zawierać WYŁĄCZNIE wpisy
# "<plik>.age" — klucze publiczne są w keys.nix.
#
# Odbiorca droid-android (stara maszyna AVF, root@debian) został usunięty.
# Pliki .age zaszyfrowane jeszcze dla niego trzeba przeszyfrować:
#   cd modules/_secrets && sudo agenix -r -i /root/.ssh/id_ed25519
let
  keys = import ./keys.nix;
  inherit (keys.hosts) nixos raspberry-pi-4;

  # Laptop jest odbiorcą wszystkiego, bo to na nim edytujesz sekrety
  # (agenix -e z kluczem roota laptopa).
  allHosts = [
    nixos
    raspberry-pi-4
  ];

  mkSecret = publicKeys: {
    inherit publicKeys;
    armor = true;
  };
in
{
  "secret1.age" = mkSecret allHosts;
  "notes.age" = mkSecret allHosts;
  "trilium-etapi.age" = mkSecret allHosts;
  "nextcloud-adminpass.age" = mkSecret allHosts;
  "GITHUB_TOKEN.age" = mkSecret allHosts;
  "cloudflared-tunnel.age" = mkSecret allHosts;
  "cachix-authtoken-token.age" = mkSecret allHosts;
  "ollama-api-key.age" = mkSecret allHosts;
  "google-api-key.age" = mkSecret allHosts;
  "hermes-env.age" = mkSecret allHosts;
  "opencode.age" = mkSecret allHosts;
  "open-webui-keys.age" = mkSecret allHosts;
  "llmgateway-api-key.age" = mkSecret allHosts;
  "openrouter-api-key.age" = mkSecret allHosts;
  # Hasło Basic Auth ttyd (nginx) — osobne, NIE hasło admina Nextcloud.
  "ttyd-password.age" = mkSecret allHosts;
  # Wi-Fi RPi (modules/hosts/raspberry-pi-4/wifi.nix): WIFI_SSID=…, WIFI_PSK=…
  "wifi.age" = mkSecret allHosts;
}
