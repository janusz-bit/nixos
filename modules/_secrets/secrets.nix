# Reguły agenix CLI (agenix -e / -r). Plik może zawierać WYŁĄCZNIE wpisy
# "<plik>.age" — klucze publiczne są w keys.nix.
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
  # Wi-Fi RPi (modules/hosts/raspberry-pi-4/network.nix): WIFI_SSID=…, WIFI_PSK=…
  "wifi.age" = mkSecret allHosts;
  # Token bota Hermesa na Matrixie (modules/hosts/raspberry-pi-4/matrix.nix):
  # MATRIX_ACCESS_TOKEN=…, opcjonalnie MATRIX_RECOVERY_KEY=…
  "hermes-matrix.age" = mkSecret allHosts;
  # Prywatny klucz SSH claude-notify (modules/claude-notify/default.nix).
  "hermes-notify-key.age" = mkSecret allHosts;
  # Prywatny klucz SSH tunelu Hermesa do LLM laptopa (modules/hosts/laptop-llm.nix).
  "hermes-llm-key.age" = mkSecret allHosts;
  # Kopia zapasowa klucza podpisywania APK Brulionu, na żaden host nie trafia.
  # Format env z nazwami sekretów CI github:janusz-bit/brulion:
  # QT_ANDROID_KEYSTORE_BASE64 (plik .jks w base64), QT_ANDROID_KEYSTORE_STORE_PASS,
  # QT_ANDROID_KEYSTORE_KEY_PASS, QT_ANDROID_KEYSTORE_ALIAS.
  "brulion-android-keystore.age" = mkSecret allHosts;
}
