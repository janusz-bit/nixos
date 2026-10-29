# claude-notify [--print] [TEKST...]  TEKST (bez argumentów: stdin) do DM.
# claude-notify [--print] --hook      JSON hooka Notification Claude Code na stdin.
# claude-notify --record              JSON hooka PermissionRequest na stdin:
#                                     zapisuje szczegóły dla --hook, nic nie wysyła.
# --print: wiadomość na stdout zamiast wysyłki (testy; deduplikacja i zużycie
# rekordów działają jak przy wysyłce).
# Zmienne key, receiver, ssh_command, format i service_user ustawia Nix
# (mkClaudeNotify w ../default.nix).

user=$(id -un)

print=false
if [[ ${1-} == --print ]]; then
  print=true
  shift
fi
mode=plain
case ${1-} in
  --hook | --record) mode=${1#--} ;;
esac

if [[ $mode != plain ]]; then
  # Hook nie może przeszkadzać sesji: każdy błąd (np. konto bez dostępu do
  # klucza, jak claude-remote) kończy się po cichu kodem 0, a stdout hooka
  # Claude Code mógłby czytać jako decyzję.
  exec 2>/dev/null
  $print || exec >/dev/null
  trap 'exit 0' EXIT
fi

fail() {
  printf 'claude-notify: %s\n' "$1" >&2
  exit 1
}

# Stan (rekordy, ostatnie wysyłki) w katalogu runtime użytkownika: tylko gdy
# katalog należy do nas; bez niego nie ma rekordów ani deduplikacji.
umask 077
state=
if [[ -n ${XDG_RUNTIME_DIR-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]]; then
  state=$XDG_RUNTIME_DIR/claude-notify
  mkdir -m 0700 "$state" 2>/dev/null || true
  if [[ -d $state && ! -L $state && -O $state ]]; then
    chmod 0700 "$state"
  else
    state=
  fi
fi

# Wszystkie tryby przez jeden program jq (format); jq wymaga każdej zmiennej,
# której program używa, także tych zbędnych w danym trybie.
input=null text='' records='[]' pane='' tmux_where='' attach=''
render() {
  jq -r "$@" --arg mode "$mode" --argjson records "$records" --arg pane "$pane" \
    --arg host "$HOSTNAME" --arg user "$user" --arg cwd "${cwd:-$PWD}" --arg tmux "$tmux_where" \
    --arg attach "$attach" --arg text "$text" -f "$format" <<<"$input"
}

if [[ $mode == plain ]]; then
  cwd=$PWD
  sid=${CLAUDE_CODE_SESSION_ID-}
  if (($#)); then
    text=$*
  else
    text=$(cat)
  fi
  [[ -n ${text//[[:space:]]/} ]] || fail "pusty tekst (podaj go jako argument albo na stdin)"
else
  input=$(cat)
  jq -e 'type == "object"' >/dev/null <<<"$input" || exit 0
  cwd=$(jq -r '.cwd // empty' <<<"$input")
  sid=$(jq -r '.session_id // empty' <<<"$input")
fi
sid=${sid//[^A-Za-z0-9_-]/_}
sid=${sid:0:64}

if [[ $mode == record ]]; then
  [[ -n $state && -n $sid ]] || exit 0
  line=$(render -c)
  {
    flock 9
    printf '%s\n' "$line" >>"$state/$sid.jsonl"
  } 9>"$state/lock"
  exit 0
fi

# Rekordy PermissionRequest tej sesji: wybiera je format (świeżość), a po
# powiadomieniu o zgodzie wszystkie są już zbędne.
if [[ $mode == hook && -n $state && -n $sid ]] &&
  [[ $(jq -r '.notification_type // empty' <<<"$input") == permission_prompt ]]; then
  {
    flock 9
    records=$(jq -cRs 'split("\n") | map(fromjson? // empty)' "$state/$sid.jsonl") || records='[]'
    rm -f "$state/$sid.jsonl"
  } 9>"$state/lock"
fi

# tmux: sesja i okno panelu, z którego działa Claude (TMUX_PANE), nie
# aktualnie oglądanego; zrzut ekranu tylko dla hooka.
if [[ -n ${TMUX-} ]]; then
  target=()
  [[ -z ${TMUX_PANE-} ]] || target=(-t "$TMUX_PANE")
  tmux_where=$(tmux display-message -p "${target[@]}" '#S:#I' 2>/dev/null) || tmux_where=
  [[ -z $tmux_where ]] || printf -v attach 'tmux attach -t %q' "${tmux_where%:*}"
  if [[ $mode == hook ]]; then
    pane=$(tmux capture-pane -p -J "${target[@]}" 2>/dev/null) || pane=
  fi
fi

msg=$(render)

# Deduplikacja: ta sama wiadomość z tej samej sesji najwyżej raz na 60 s
# (z laptopa przychodziły dwa identyczne powiadomienia naraz). Znacznik
# powstaje przed wysyłką (trwa do pół minuty), a po błędzie znika.
digest=
if [[ -n $state ]]; then
  digest=$(printf '%s\0%s' "$sid" "$msg" | sha256sum | cut -d' ' -f1)
  {
    flock 9
    now=$(date +%s)
    touch "$state/sent"
    mapfile -t recent < <(awk -v since="$((now - 60))" '$1 > since' "$state/sent")
    for entry in "${recent[@]}"; do
      if [[ ${entry#* } == "$digest" ]]; then
        echo "claude-notify: pominięte, ta sama wiadomość poszła mniej niż 60 s temu" >&2
        exit 0
      fi
    done
    printf '%s\n' "${recent[@]}" "$now $digest" >"$state/sent"
  } 9>"$state/lock"
fi

if $print; then
  printf '%s\n' "$msg"
  exit 0
fi

# Konto usługi (brama i jej procesy) woła odbiornik wprost; klucz
# hermes:hermes 0440 jest dla innych członków grupy hermes.
if [[ -n $receiver && $user == "$service_user" ]]; then
  send=("$receiver")
else
  [[ -r $key ]] || fail "brak dostępu do klucza $key (konto $user)"
  send=("${ssh_command[@]}")
fi
"${send[@]}" <<<"$msg" && exit 0
status=$?
if [[ -n $digest ]]; then
  {
    flock 9
    awk -v digest="$digest" '$2 != digest' "$state/sent" >"$state/sent.new"
    mv "$state/sent.new" "$state/sent"
  } 9>"$state/lock"
fi
fail "wysyłka nie powiodła się (kod $status)"
