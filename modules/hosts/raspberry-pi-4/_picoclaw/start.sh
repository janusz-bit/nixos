# Uzupełnia konfigurację z Nixa (CONFIG_TEMPLATE) o sesję bota Matrix
# i klucz bazy E2EE, zapisuje ją w katalogu runtime (0600 przez UMask
# jednostki) i uruchamia gateway. Klucz powstaje raz w katalogu stanu: chroni
# tylko bazę kluczy, która leży obok niego, więc nie jest sekretem agenix.
# Zmienne: CONFIG_TEMPLATE, SESSION (runtimeEnv), STATE_DIRECTORY,
# RUNTIME_DIRECTORY (systemd).
passphrase=$STATE_DIRECTORY/matrix-crypto-passphrase

if [ ! -s "$passphrase" ]; then
  head -c 32 /dev/urandom | base64 -w0 >"$passphrase.tmp"
  mv "$passphrase.tmp" "$passphrase"
fi

PICOCLAW_CONFIG=$RUNTIME_DIRECTORY/config.json
export PICOCLAW_CONFIG
jq --slurpfile session "$SESSION" --rawfile passphrase "$passphrase" \
  '.channel_list.matrix.settings += {
    user_id: $session[0].user_id,
    access_token: $session[0].access_token,
    device_id: $session[0].device_id,
    crypto_passphrase: $passphrase
  }' "$CONFIG_TEMPLATE" >"$PICOCLAW_CONFIG"

exec picoclaw gateway
