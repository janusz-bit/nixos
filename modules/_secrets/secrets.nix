# Reguły agenix CLI (agenix -e / -r). Plik może zawierać WYŁĄCZNIE wpisy
# "<plik>.age" — klucze publiczne są w keys.nix.
let
  inherit ((import ./keys.nix).hosts) nixos raspberry-pi-4;

  # Laptop jest odbiorcą wszystkiego, bo to na nim edytujesz sekrety
  # (agenix -e z kluczem roota laptopa).
  toAllHosts = {
    publicKeys = [
      nixos
      raspberry-pi-4
    ];
    armor = true;
  };
in
{
  "secret1.age" = toAllHosts;
  "notes.age" = toAllHosts;
  "trilium-etapi.age" = toAllHosts;
  "nextcloud-adminpass.age" = toAllHosts;
  "GITHUB_TOKEN.age" = toAllHosts;
  "cachix-authtoken-token.age" = toAllHosts;
  "ollama-api-key.age" = toAllHosts;
  "google-api-key.age" = toAllHosts;
  "opencode.age" = toAllHosts;
  "open-webui-keys.age" = toAllHosts;
  "llmgateway-api-key.age" = toAllHosts;
  "openrouter-api-key.age" = toAllHosts;
  # Wi-Fi RPi (modules/hosts/raspberry-pi-4/network.nix): WIFI_SSID=…, WIFI_PSK=…
  "wifi.age" = toAllHosts;
  # Kopia zapasowa klucza podpisywania APK Brulionu, na żaden host nie trafia.
  # Format env z nazwami sekretów CI github:janusz-bit/brulion:
  # QT_ANDROID_KEYSTORE_BASE64 (plik .jks w base64), QT_ANDROID_KEYSTORE_STORE_PASS,
  # QT_ANDROID_KEYSTORE_KEY_PASS, QT_ANDROID_KEYSTORE_ALIAS.
  "brulion-android-keystore.age" = toAllHosts;
  # Kopia zapasowa klucza podpisywania F-Droid Brulionu, na żaden host nie trafia.
  "brulion-fdroid-key.age" = toAllHosts;
}
