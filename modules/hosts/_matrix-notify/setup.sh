# Jednorazowo: konto bota powiadomień i jego pokój (alias ROOM_ALIAS_NAME,
# bez E2EE, zaproszony właściciel). Na stdout tylko nagłówek z tokenem bota
# do zaszyfrowania jako matrix-notify.age; hasło bota jest losowe i nigdzie
# nie zostaje, bo bot używa wyłącznie tokenu.
# Zmienne (runtimeEnv): HOMESERVER, OWNER, OWNER_ID, BOT, BOT_ID,
# ROOM_ALIAS_NAME, REGISTRATION_TOKEN_FILE.
if [ -t 1 ]; then
  echo "matrix-notify-setup: wypisuje token bota; przekaż wyjście do agenix (nagłówek hosts/matrix-notify.nix)" >&2
  exit 2
fi

api=$HOMESERVER/_matrix/client/v3

# 200: nazwa wolna, 400 (M_USER_IN_USE): zajęta, inaczej serwer nie odpowiada.
availability() {
  curl -sS --max-time 10 -o /dev/null -w '%{http_code}' \
    "$api/register/available?username=$1"
}

case $(availability "$OWNER") in
  400) ;;
  200)
    echo "matrix-notify-setup: najpierw zarejestruj konto @$OWNER (pierwsze konto zostaje administratorem serwera, rpi-matrix)" >&2
    exit 1
    ;;
  *)
    echo "matrix-notify-setup: serwer Matrix $HOMESERVER nie odpowiada" >&2
    exit 1
    ;;
esac

if [ "$(availability "$BOT")" != 200 ]; then
  echo "matrix-notify-setup: konto $BOT_ID już istnieje; w pokoju #admins: !admin users deactivate $BOT_ID i !admin rooms alias remove $ROOM_ALIAS_NAME" >&2
  exit 1
fi

# Hasło i token rejestracji przez env, nie przez argv (widoczne w ps).
PASSWORD=$(head -c 32 /dev/urandom | base64 -w0)
export PASSWORD

# AUTH: pole auth żądania jako JSON.
register() {
  jq -n --arg username "$BOT" \
    '{$username, password: env.PASSWORD, initial_device_display_name: "matrix-notify"} + (env.AUTH | fromjson)' |
    curl -sS --max-time 30 -H 'Content-Type: application/json' \
      --data-binary @- "$api/register"
}

# Pierwsze żądanie bez auth otwiera sesję UIA, drugie podaje token rejestracji.
uia=$(AUTH='{}' register | jq -r '.session // empty')
if [ -z "$uia" ]; then
  echo "matrix-notify-setup: serwer nie otworzył sesji rejestracji" >&2
  exit 1
fi

AUTH=$(jq -n --rawfile token "$REGISTRATION_TOKEN_FILE" --arg session "$uia" \
  '{auth: {type: "m.login.registration_token", token: ($token | rtrimstr("\n")), $session}}')
export AUTH
response=$(register)
if ! token=$(jq -er .access_token <<<"$response"); then
  echo "matrix-notify-setup: rejestracja $BOT_ID nieudana: $(jq -r '.error // .' <<<"$response")" >&2
  exit 1
fi
header="Authorization: Bearer $token"

# trusted_private_chat: właściciel dostaje te same uprawnienia co bot.
if ! jq -n --arg owner "$OWNER_ID" --arg alias "$ROOM_ALIAS_NAME" '{
  preset: "trusted_private_chat",
  is_direct: true,
  invite: [$owner],
  room_alias_name: $alias,
  name: "Powiadomienia agentów AI"
}' | curl -fsS --max-time 30 -o /dev/null -H @<(printf '%s\n' "$header") \
  -H 'Content-Type: application/json' --data-binary @- "$api/createRoom"; then
  echo "matrix-notify-setup: nie powstał pokój #$ROOM_ALIAS_NAME; w pokoju #admins: !admin users deactivate $BOT_ID (i !admin rooms alias remove $ROOM_ALIAS_NAME, jeśli alias istnieje), potem ponów" >&2
  exit 1
fi

printf '%s\n' "$header"
