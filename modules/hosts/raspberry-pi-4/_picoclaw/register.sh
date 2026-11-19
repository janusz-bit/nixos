# Rejestruje konto bota na serwerze Matrix i zapisuje jego sesję (user_id,
# access_token, device_id) w katalogu stanu picoclaw. Hasło jest losowe
# i nigdzie nie zostaje: bot loguje się tylko tokenem dostępu.
# Zmienne: HOMESERVER, OWNER, BOT, SESSION (runtimeEnv),
# CREDENTIALS_DIRECTORY (systemd).
[ -s "$SESSION" ] && exit 0

api=$HOMESERVER/_matrix/client/v3

# 200: nazwa wolna, 400 (M_USER_IN_USE): zajęta, inaczej serwer nie odpowiada.
availability() {
  curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
    "$api/register/available?username=$1"
}

case $(availability "$OWNER") in
  400) ;;
  200)
    echo "picoclaw: najpierw zarejestruj konto @$OWNER (pierwsze konto zostaje administratorem serwera, rpi-matrix)" >&2
    exit 1
    ;;
  *)
    echo "picoclaw: serwer Matrix $HOMESERVER nie odpowiada" >&2
    exit 1
    ;;
esac

if [ "$(availability "$BOT")" != 200 ]; then
  echo "picoclaw: konto @$BOT już istnieje, a brak $SESSION; usuń je w pokoju #admins (!admin users deactivate @$BOT) albo zmień nazwę bota" >&2
  exit 1
fi

# Hasło i token przez env i plik, nie przez argv (widoczne w ps).
PASSWORD=$(head -c 32 /dev/urandom | base64 -w0)
export PASSWORD

# AUTH: pole auth żądania jako JSON (z tokenem rejestracji, więc przez env).
register() {
  jq -n --arg username "$BOT" \
    '{$username, password: env.PASSWORD, initial_device_display_name: "picoclaw"} + (env.AUTH | fromjson)' |
    curl -sS --max-time 30 -H 'Content-Type: application/json' \
      --data-binary @- "$api/register"
}

# Pierwsze żądanie bez auth otwiera sesję UIA, drugie podaje token rejestracji.
uia=$(AUTH='{}' register | jq -r '.session // empty')
if [ -z "$uia" ]; then
  echo "picoclaw: serwer nie otworzył sesji rejestracji" >&2
  exit 1
fi

AUTH=$(jq -n --rawfile token "$CREDENTIALS_DIRECTORY/registration-token" --arg session "$uia" \
  '{auth: {type: "m.login.registration_token", token: ($token | rtrimstr("\n")), $session}}')
export AUTH
response=$(register)
if ! jq -e '.access_token' >/dev/null <<<"$response"; then
  echo "picoclaw: rejestracja @$BOT nieudana: $(jq -r '.error // .' <<<"$response")" >&2
  exit 1
fi

umask 077
jq '{user_id, access_token, device_id}' <<<"$response" >"$SESSION.tmp"
mv "$SESSION.tmp" "$SESSION"
