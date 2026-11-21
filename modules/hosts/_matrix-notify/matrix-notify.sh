# Wiadomość od bota do pokoju powiadomień (alias ROOM_ALIAS).
# Zmienne (runtimeEnv): HOMESERVER, ROOM_ALIAS, TOKEN_FILE (nagłówek
# Authorization dla `curl -H @plik`, token nigdy na linii poleceń).
usage() {
  echo "usage: matrix-notify [-t title] [-q] message" >&2
  exit 2
}

title=""
# m.notice wycisza domyślna reguła push .m.rule.suppress_notices: wiadomość
# jest w pokoju, ale telefon nie dzwoni.
msgtype=m.text
while getopts t:q opt; do
  case $opt in
    t) title=$OPTARG ;;
    q) msgtype=m.notice ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))
[ $# -gt 0 ] || usage

if [ ! -r "$TOKEN_FILE" ]; then
  echo "matrix-notify: brak tokenu bota dla tego konta ($TOKEN_FILE)" >&2
  exit 1
fi

api=$HOMESERVER/_matrix/client/v3
uri() { jq -rn --arg value "$1" '$value | @uri'; }

room=$(curl -fsS --max-time 10 -H @"$TOKEN_FILE" \
  "$api/directory/room/$(uri "$ROOM_ALIAS")" | jq -er .room_id)

jq -n --arg msgtype "$msgtype" --arg title "$title" --arg message "$*" '{
  $msgtype,
  body: (if $title == "" then $message else "\($title)\n\($message)" end),
  format: "org.matrix.custom.html",
  formatted_body: (
    (if $title == "" then "" else "<b>\($title | @html)</b><br>" end)
    + ($message | @html | gsub("\n"; "<br>"))
  )
}' |
  curl -fsS --max-time 10 -o /dev/null -X PUT \
    -H @"$TOKEN_FILE" -H 'Content-Type: application/json' --data-binary @- \
    "$api/rooms/$(uri "$room")/send/m.room.message/$(date +%s%N)-$$"
