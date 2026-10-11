# claude-notify: powiadomienia Claude Code do DM na Matrixie przez Hermesa.
#
# Po co: Claude Code daje znać (skończone dłuższe zadanie, pytanie, które go
# blokuje), gdy nikt nie patrzy w terminal. Bez LLM: `hermes send` na RPi
# wysyła gotowy tekst adapterem Matrixa Hermesa (konto bota, E2EE) do DM
# z MATRIX_HOME_ROOM (matrix.nix).
#
# Droga wiadomości:
# - laptop (nixos-claude-notify): claude-notify → ssh przez tunel cloudflared
#   (ssh.<domena>) → sshd RPi, które widzi połączenie z localhost → konto
#   hermes z wymuszonym poleceniem hermes-notify-receive → hermes send;
# - RPi (rpi-claude-notify) jako nixos: to samo przez ssh na localhost;
# - RPi jako hermes (brama i jej procesy, np. `claude -p`): odbiornik wprost.
#
# Granica zaufania: klucz z hermes-notify-key.age (laptop: dinosaur 0400; RPi:
# hermes:hermes 0440, nixos czyta przez grupę) loguje tylko na konto hermes,
# tylko z 127.0.0.1/::1 (tunel i localhost, nie z LAN-u), z `restrict` (bez pty,
# przekierowań i agenta) i z wymuszonym poleceniem. Odbiornik ignoruje
# SSH_ORIGINAL_COMMAND i argumenty: bierze wyłącznie tekst ze stdin (do 3500
# bajtów, najwyżej 30 wiadomości na godzinę) i wysyła go do jednego, stałego
# DM. Wyciek klucza pozwala więc najwyżej zaspamować ten DM w granicach limitu.
# Samo konto hermes nic nie zyskuje: `hermes send` mogło wywołać i bez tego.
# Klient przypina klucz hosta RPi (keys.sshHostKeys) i pomija ssh_config
# (-F /dev/null), bo base-ssh ma `Host ssh.*` → User root.
#
# Claude Code: skill hermes-notify (kiedy i jak pisać) oraz ustawienia
# zarządzane z hookami Notification i PermissionRequest i regułą allow
# (claudeCodeSettings niżej).
# claude-notify nie trafia do skillPackages (modules/skills/default.nix): cel
# ssh, ścieżka klucza i odbiornik zależą od hosta, więc pakiet powstaje tutaj.
#
# Wiadomość (messageFormat): Hermes zamienia Markdown na HTML Matrixa
# i odrzuca nieznane tagi, więc wolny tekst jest escapowany, a ścieżki
# i polecenia idą w kod. Nagłówek: host, konto, katalog roboczy, w tmux sesja
# i okno. Prośba o zgodę: narzędzie i argumenty z rekordu, który zapisał hook
# PermissionRequest (`claude-notify --record`, plik sesji
# w $XDG_RUNTIME_DIR/claude-notify, 0700); bez rekordu (np. sieć komendy
# w sandboksie) tytuł/treść powiadomienia i okno dialogu z ekranu tmux.
# AskUserQuestion idzie jako pytania z numerowanymi opcjami (numery jak
# w oknie Claude Code), a ExitPlanMode jako plan w bloku markdown ze ścieżką
# pliku planu.
# Całość do 3300 bajtów, bo odbiornik tnie przy 3500 (urwałby płot bloku).
# Ta sama wiadomość z tej samej sesji idzie najwyżej raz na 60 s.
#
# Test bez wysyłki: `claude-notify --print …` wypisuje gotową wiadomość
# (deduplikacja i rekordy działają jak przy wysyłce), np.
# `jq -n '{session_id:"s",cwd:"/tmp",notification_type:"permission_prompt",message:"m"}' | claude-notify --print --hook`.
# Po wdrożeniu (RPi dopiero po merge do master i `update`, laptop po
# `update-local`): `echo test | claude-notify` na obu hostach, na RPi także
# `sudo -u hermes claude-notify test` (ścieżka bez ssh). Odbiornik: pusty stdin
# albo 31. wiadomość w ciągu godziny → kod 1 i komunikat na stderr. Hook: w
# sesji Claude Code w tmux polecenie, które wymaga zgody (prompt uprawnień).
{ customTop, lib, ... }:
let
  keys = import "${customTop.secretsDir}/keys.nix";

  # Dopóki pliku nie ma w gicie (flake widzi tylko śledzone pliki), funkcja jest
  # wyłączona, a ewaluacja tylko ostrzega.
  secretFile = customTop.secretsDir + "/hermes-notify-key.age";
  hasSecret = builtins.pathExists secretFile;

  rpi = "raspberry-pi-4";
  hermesUser = "hermes";

  # Skrypt: clientScript (tryby, stan, deduplikacja, wysyłka), format
  # wiadomości i rekordów: messageFormat.
  mkClaudeNotify =
    {
      pkgs,
      ssh,
      tmux,
      key,
      target,
      sshOptions ? [ ],
      receiver ? null,
    }:
    let
      # HostKeyAlias: ten sam wpis niezależnie od celu (tunel albo localhost).
      knownHosts = pkgs.writeText "hermes-notify-known-hosts" "${rpi} ${keys.sshHostKeys.${rpi}}\n";
      # Limit z zapasem: wysyłka przez `hermes send` na RPi trwa 22–31 s
      # (zmierzone 2026-10-11), a przy 20 s wiadomość dochodziła mimo kodu 124.
      # -T: odbiornik nie dostaje pty (`restrict`), więc bez ostrzeżenia ssh.
      sshCommand = [
        "timeout"
        "60"
        "ssh"
        "-T"
        "-F"
        "/dev/null"
        "-i"
        key
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "BatchMode=yes"
        "-o"
        "ConnectTimeout=10"
        "-o"
        "StrictHostKeyChecking=yes"
        "-o"
        "HostKeyAlias=${rpi}"
        "-o"
        "UserKnownHostsFile=${knownHosts}"
      ]
      ++ sshOptions
      ++ [ "${hermesUser}@${target}" ];
    in
    pkgs.writeShellApplication {
      name = "claude-notify";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
        pkgs.util-linux
        ssh
        tmux
      ];
      text = ''
        key=${lib.escapeShellArg key}
        receiver=${lib.escapeShellArg (lib.optionalString (receiver != null) (lib.getExe receiver))}
        ssh_command=(${lib.escapeShellArgs sshCommand})
        format=${pkgs.writeText "claude-notify.jq" messageFormat}
        service_user=${hermesUser}
      ''
      + clientScript;
    };

  # Ustawienia zarządzane Claude Code (każdy użytkownik i projekt hosta).
  # Notification: prośby o zgodę i pytania MCP; koniec pracy zgłasza skill
  # hermes-notify (modules/skills), dlatego bez Stop i idle_prompt.
  # PermissionRequest: rusza w chwili otwarcia okna zgody i daje narzędzie
  # z argumentami, których Notification nie ma (--record je tylko zapisuje).
  # async: hook asynchroniczny z definicji nie wpływa na decyzję i nie
  # opóźnia okna; zapis trwa ułamek sekundy, a Notification przychodzi ~6 s
  # później. Hook synchroniczny bez wyjścia z kodem 0 też nie decyduje, ale
  # okno czekałoby na start jq. Nie obejmuje sieci komend w sandboksie (wtedy
  # Notification bez rekordu, z wycinkiem ekranu).
  # `Bash(claude-notify *)` to w 2.1.285 `^claude-notify( .*)?$`, więc obejmuje
  # też samo `claude-notify` z tekstem na stdin.
  # Obejmuje też `claude -p` pluginu claude-subscription-directsdk Hermesa
  # (--setting-sources "" nie wyłącza ustawień zarządzanych), ale go nie
  # zmienia: plugin daje --tools "" (bez Bash), --disable-slash-commands (bez
  # skilli) i --permission-mode dontAsk (bez próśb o zgodę, więc bez
  # PermissionRequest), a jego serwer MCP nie prosi o elicitation.
  claudeCodeSettings =
    pkgs: claudeNotify:
    let
      hook = flag: {
        type = "command";
        command = "${lib.escapeShellArg (lib.getExe claudeNotify)} ${flag}";
        async = true;
      };
    in
    {
      "claude-code/managed-settings.d/50-hermes-notify.json".source =
        (pkgs.formats.json { }).generate "50-hermes-notify.json"
          {
            permissions.allow = [ "Bash(claude-notify *)" ];
            hooks = {
              Notification = [
                {
                  matcher = "permission_prompt|elicitation_dialog";
                  hooks = [ (hook "--hook") ];
                }
              ];
              PermissionRequest = [ { hooks = [ (hook "--record" // { timeout = 10; }) ]; } ];
            };
          };
    };

  clientScript = ''
    # claude-notify [--print] [TEKST...]  TEKST (bez argumentów: stdin) do DM.
    # claude-notify [--print] --hook      JSON hooka Notification Claude Code na stdin.
    # claude-notify --record              JSON hooka PermissionRequest na stdin:
    #                                     zapisuje szczegóły dla --hook, nic nie wysyła.
    # --print: wiadomość na stdout zamiast wysyłki (testy; deduplikacja i zużycie
    # rekordów działają jak przy wysyłce).
    # Zmienne key, receiver, ssh_command, format i service_user ustawia Nix
    # (mkClaudeNotify w claude-notify.nix).

    user=$(id -un)

    print=false
    if [[ ''${1-} == --print ]]; then
      print=true
      shift
    fi
    mode=plain
    case ''${1-} in
      --hook) mode=hook ;;
      --record) mode=record ;;
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
    if [[ -n ''${XDG_RUNTIME_DIR-} && -d $XDG_RUNTIME_DIR && -O $XDG_RUNTIME_DIR ]]; then
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
    input=null text=''' records='[]' pane=''' tmux_where=''' attach='''
    render() {
      jq -r "$@" --arg mode "$mode" --argjson records "$records" --arg pane "$pane" \
        --arg host "$HOSTNAME" --arg user "$user" --arg cwd "''${cwd:-$PWD}" --arg tmux "$tmux_where" \
        --arg attach "$attach" --arg text "$text" -f "$format" <<<"$input"
    }

    if [[ $mode == plain ]]; then
      cwd=$PWD
      sid=''${CLAUDE_CODE_SESSION_ID-}
      if (($#)); then
        text=$*
      else
        text=$(cat)
      fi
      [[ -n ''${text//[[:space:]]/} ]] || fail "pusty tekst (podaj go jako argument albo na stdin)"
    else
      input=$(cat)
      jq -e 'type == "object"' >/dev/null <<<"$input" || exit 0
      cwd=$(jq -r '.cwd // empty' <<<"$input")
      sid=$(jq -r '.session_id // empty' <<<"$input")
    fi
    sid=''${sid//[^A-Za-z0-9_-]/_}
    sid=''${sid:0:64}

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
        if [[ -f $state/$sid.jsonl ]]; then
          records=$(jq -cRs 'split("\n") | map(fromjson? // empty)' "$state/$sid.jsonl") || records='[]'
          rm -f "$state/$sid.jsonl"
        fi
      } 9>"$state/lock"
    fi

    # tmux: sesja i okno panelu, z którego działa Claude (TMUX_PANE), nie
    # aktualnie oglądanego; zrzut ekranu tylko dla hooka.
    if [[ -n ''${TMUX-} ]]; then
      target=()
      [[ -z ''${TMUX_PANE-} ]] || target=(-t "$TMUX_PANE")
      if tmux_where=$(tmux display-message -p "''${target[@]}" '#S:#I' 2>/dev/null) && [[ -n $tmux_where ]]; then
        printf -v attach 'tmux attach -t %q' "''${tmux_where%:*}"
      else
        tmux_where=
      fi
      if [[ $mode == hook ]]; then
        pane=$(tmux capture-pane -p -J "''${target[@]}" 2>/dev/null) || pane=
      fi
    fi

    msg=$(render)

    # Deduplikacja: ta sama wiadomość z tej samej sesji najwyżej raz na 60 s
    # (z laptopa przychodziły dwa identyczne powiadomienia naraz). Znacznik
    # powstaje przed wysyłką (trwa do pół minuty), a po błędzie znika.
    digest=
    if [[ -n $state ]]; then
      digest=$(printf '%s\0%s' "$sid" "$msg" | sha256sum | cut -d' ' -f1)
      duplicate=false
      {
        flock 9
        now=$(date +%s)
        touch "$state/sent"
        mapfile -t recent < <(awk -v since="$((now - 60))" '$1 > since' "$state/sent")
        for entry in "''${recent[@]}"; do
          [[ ''${entry#* } != "$digest" ]] || duplicate=true
        done
        if ! $duplicate; then
          printf '%s\n' "''${recent[@]}" "$now $digest" >"$state/sent"
        fi
      } 9>"$state/lock"
      if $duplicate; then
        echo "claude-notify: pominięte, ta sama wiadomość poszła mniej niż 60 s temu" >&2
        exit 0
      fi
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
      send=("''${ssh_command[@]}")
    fi
    status=0
    "''${send[@]}" <<<"$msg" || status=$?
    if ((status)); then
      if [[ -n $digest ]]; then
        {
          flock 9
          awk -v digest="$digest" '$2 != digest' "$state/sent" >"$state/sent.new"
          mv "$state/sent.new" "$state/sent"
        } 9>"$state/lock"
      fi
      fail "wysyłka nie powiodła się (kod $status)"
    fi
  '';

  messageFormat = ''
    # claude-notify: format wiadomości (Markdown dla Hermesa) i rekordy hooka
    # PermissionRequest. Opis w nagłówku claude-notify.nix.
    #
    # $mode: "record" — stdin to JSON PermissionRequest, wynik to jedna linia JSON;
    # "hook" — stdin to JSON Notification; "plain" — jq -n, tekst w $text.
    #
    # Hermes zamienia Markdown na HTML (python-markdown: fenced_code, tables,
    # nl2br, sane_lists) i odrzuca nieznane tagi, więc `foo <x>` dochodzi jako
    # `foo `. Dlatego tekst spoza kodu przechodzi przez esc, a wartości maszynowe
    # (ścieżki, polecenia) idą w kod: tam `<` i `*` zostają dosłowne.

    def str: if type == "string" then . elif . == null then "" else tojson end;
    def oneline: gsub("\\s+"; " ") | sub("^ "; "") | sub(" $"; "");
    def cut($n): if length > $n then .[0:$n - 1] + "…" else . end;

    # Encje zamiast `\<`: python-markdown nie zna takiej ucieczki i zostawia
    # ukośnik. `&` najpierw, żeby dosłowne `&lt;` nie stało się `<`.
    def esc:
      oneline
      | gsub("&"; "&amp;") | gsub("<"; "&lt;") | gsub(">"; "&gt;")
      | gsub("(?<c>[\\\\`*_\\[\\]#|])"; "\\\(.c)");

    def longest_backticks: [scan("`+") | length] | max // 0;

    # Kod w linii: płot dłuższy od każdego ciągu backticków w treści; spacje przy
    # backticku na brzegu (python-markdown je obcina).
    def code:
      oneline as $s
      | ("`" * (($s | longest_backticks) + 1)) as $f
      | if ($s | test("^`|`$")) then "\($f) \($s) \($f)" else "\($f)\($s)\($f)" end;

    # Blok kodu: fenced_code zamyka blok tylko płotem identycznym z otwierającym.
    def block($lang):
      ("`" * ([3, longest_backticks + 1] | max)) as $f
      | "\($f)\($lang)\n\(.)\n\($f)";

    # Najwyżej $n linii po $w znaków i $b bajtów łącznie; ucięcie widać jako `…`.
    def fit($n; $w; $b):
      (split("\n") | map(sub("\\s+$"; "") | cut($w))) as $all
      | reduce $all[] as $l ({out: [], bytes: 0, full: false};
          ($l | utf8bytelength + 1) as $size
          | if .full or (.out | length) >= $n or .bytes + $size > $b then .full = true
            else .out += [$l] | .bytes += $size end)
      | (.out | join("\n")) + (if (.out | length) < ($all | length) then "\n…" else "" end);

    def is_path_tool: IN("Read", "Edit", "MultiEdit", "Write", "NotebookEdit");

    # Rekord: tylko pola potrzebne do wiadomości, z góry przycięte.
    def record:
      (.tool_name | str) as $t
      | .tool_input as $i
      | {
          t: now,
          tool: ($t | cut(100)),
          input: (
            if $t == "Bash" then
              {description: ($i.description | str | oneline | cut(300)), command: ($i.command | str | cut(3000))}
            elif ($t | is_path_tool) then {path: ($i.file_path // $i.notebook_path | str | cut(500))}
            elif $t == "WebFetch" then {url: ($i.url | str | cut(500))}
            elif $t == "WebSearch" then {query: ($i.query | str | cut(300))}
            elif ($t | IN("Grep", "Glob")) then {pattern: ($i.pattern | str | cut(300)), path: ($i.path | str | cut(300))}
            elif $t == "AskUserQuestion" then
              {questions: [($i.questions // [])[0:4][] | {
                header: (.header | str | oneline | cut(40)),
                question: (.question | str | oneline | cut(300)),
                multi: (.multiSelect == true),
                options: [(.options // [])[0:6][] | {
                  label: (.label | str | oneline | cut(100)),
                  description: (.description | str | oneline | cut(200))
                }]
              }]}
            elif $t == "ExitPlanMode" then {plan: ($i.plan | str | cut(3000)), path: ($i.planFilePath | str | cut(300))}
            else {json: ($i | tojson | cut(1000))}
            end
          )
        };

    # Pytania AskUserQuestion: nagłówek, pytanie, numerowane opcje (numery jak
    # w oknie Claude Code; ostatnia pozycja okna, własna odpowiedź, nie ma
    # numeru tutaj). Pusta linia przed listą: python-markdown nie przerywa
    # akapitu listą. $compact: bez opisów opcji, krótsze teksty.
    def questions($compact):
      [.questions[]
       | (if $compact then 150 else 300 end) as $qw
       | (if .header != "" then "**\(.header | esc)** — " else "" end)
         + (.question | cut($qw) | esc)
         + (if .multi then " _(można wybrać kilka)_" else "" end)
         + "\n\n"
         + ([.options | to_entries[]
             | "\(.key + 1). " + (.value.label | cut(if $compact then 60 else 100 end) | esc)
               + if $compact or .value.description == "" then "" else " — " + (.value.description | esc) end]
            | join("\n"))
      ] | join("\n\n");

    # Jedno wywołanie narzędzia; $compact (gdy pełna wiadomość przekracza limit):
    # bez bloków, krótsze pola.
    def detail($compact; $b):
      .tool as $t
      | .input as $i
      | (if $compact then 100 else 300 end) as $w
      | if $i | has("questions") then $i | questions($compact)
        elif $i | has("plan") then
          (if $compact then ($i.plan | split("\n") | map(select(test("\\S")))[0] // "" | cut(100) | esc)
           else $i.plan | sub("\\s+$"; "") | fit(15; 160; $b) | block("markdown") end)
          + if $i.path != "" then "\n" + ($i.path | code) else "" end
        else
          "**\($t | esc)**"
            + if $t == "Bash" then
                (if $i.description != "" then " — " + ($i.description | cut($w) | esc) else "" end)
                + if $i.command == "" then ""
                  elif $compact then " " + ($i.command | split("\n")[0] | cut(80) | code)
                  else "\n" + ($i.command | fit(12; 160; $b) | block("bash"))
                  end
              elif $i | has("url") then " " + ($i.url | cut($w) | code)
              elif $i | has("query") then " " + ($i.query | cut($w) | code)
              elif $i | has("pattern") then
                " " + ($i.pattern | cut($w) | code)
                + if $i.path != "" then " w " + ($i.path | cut($w) | code) else "" end
              elif $i | has("path") then " " + ($i.path | cut($w) | code)
              elif $compact then ""
              else "\n" + ($i.json | fit(12; 160; $b) | block("json"))
              end
        end;

    # Okno świeżości: permission_prompt przychodzi ~6 s po otwarciu okna zgody
    # (dłużej, gdy użytkownik coś pisze), więc 30 s obejmuje bieżącą prośbę.
    # Prośba sprzed chwili, na którą odpowiedziano przed upływem 6 s, nie
    # dostała własnego powiadomienia i jej rekord został: odpada, bo bierzemy
    # tylko rekordy do 2 s przed najnowszym (równoległe wywołania przychodzą
    # w ~200 ms, a odpowiedź człowieka i kolejne wywołanie trwają dłużej).
    def fresh_records:
      $records
      | map(select(type == "object" and (.t | type) == "number" and .t >= now - 30 and (.input | type) == "object"))
      | sort_by(.t)
      | (last.t // 0) as $newest
      | map(select(.t >= $newest - 2));

    def is_blank: gsub("[\\s\\x{2500}-\\x{257F}]"; "") == "";
    def is_rule: test("[\\x{2500}\\x{2501}\\x{2504}-\\x{250B}\\x{254C}-\\x{254F}\\x{2550}]{20,}");

    # Zrzut ekranu (tylko bez rekordu): okno dialogu, czyli wszystko po ostatniej
    # linii poziomej (dolna ramka nie liczy się), bez bocznego panelu (pionowa
    # kreska dalej niż 40 znaków od lewej) i ramek; najwyżej 20 ostatnich linii
    # po 100 znaków.
    def excerpt:
      ($pane | split("\n") | map(sub("\\s+$"; ""))
        | until(length == 0 or (last | is_blank | not); .[:-1])) as $lines
      | ($lines | to_entries | map(select(.value | is_rule)) | last.key // -1) as $rule
      | $lines[$rule + 1:]
      | map(
          (if .[40:] | test("[│┃]") then .[0:40] + (.[40:] | sub("\\s*[│┃].*$"; "")) else . end)
          | sub("^\\s*[│┃] ?"; "") | sub("\\s+$"; "")
          | select(is_blank | not)
          | cut(100)
        )
      | reverse
      | reduce .[] as $l ({out: [], bytes: 0, full: false};
          ($l | utf8bytelength + 1) as $size
          | if .full or (.out | length) >= 20 or .bytes + $size > 1800 then .full = true
            else .out = [$l] + .out | .bytes += $size end)
      | .out
      | if length == 0 then "" else "\n" + (join("\n") | block("")) end;

    # Emoji jako ucieczki: źródło zostaje bez emoji.
    def pause: "\u23f8\ufe0f";

    def header:
      "\ud83e\udd16 **\($host | esc)** · \($user | esc) · "
      + ($cwd | split("/") | map(select(. != "")) | last // "/" | cut(60) | code)
      + if $tmux != "" then " · tmux " + ($tmux | cut(60) | code) else "" end;

    def hint:
      if $attach != "" then "\n\nOdpowiedz w terminalu: " + ($attach | code) else "" end;

    def what:
      (.message | str | oneline) as $m
      | (.title | str | oneline) as $t
      | (if $t != "" and $t != $m then "\($t): \($m)" else $m end)
      | if . == "" then "" else ": " + (cut(300) | esc) end;

    def body($compact):
      (.notification_type | str) as $type
      | if $type == "permission_prompt" and (fresh_records | length) > 0 then
          fresh_records as $recs
          | ($recs[0:3]) as $shown
          | (2400 / ($shown | length) | floor) as $b
          | ($shown | map(.tool)) as $tools
          | (if ($tools | all(. == "AskUserQuestion")) then "\u2753 **Claude pyta**\n\n"
             elif ($tools | all(. == "ExitPlanMode")) then "\ud83d\udccb **Claude prosi o akceptację planu**\n"
             else "\(pause) **Claude czeka na zgodę**: " end)
            + ([$shown[] | detail($compact; $b)] | join("\n\n"))
            + if ($recs | length) > 3 then "\n\n… i jeszcze \(($recs | length) - 3)" else "" end
        else
          (if $type == "permission_prompt" then "\(pause) **Claude czeka na zgodę**"
           elif $type == "elicitation_dialog" then "\(pause) **Claude czeka na odpowiedź** (pytanie serwera MCP)"
           else "\(pause) **Claude czeka** (\($type | esc))"
           end)
          + what
          + if $compact then "" else excerpt end
        end;

    if $mode == "record" then record
    elif $mode == "hook" then
      (header + "\n" + body(false) + hint) as $full
      | if ($full | utf8bytelength) <= 3300 then $full else header + "\n" + body(true) + hint end
    else header + "\n" + $text
    end
  '';
in
{
  flake.modules.nixos.rpi-claude-notify =
    { config, pkgs, ... }:
    let
      cfg = config.services.hermes-agent;
      # Bez hermes-matrix.age matrix.nix nie ustawia pokoju (i tylko ostrzega).
      room = cfg.environment.MATRIX_HOME_ROOM or null;
      enable = hasSecret && room != null;

      receiver = pkgs.writeShellApplication {
        name = "hermes-notify-receive";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          gnused
          util-linux
        ];
        text = ''
          # Argumenty i SSH_ORIGINAL_COMMAND są ignorowane: jedyne wejście to
          # tekst na stdin, cel jest stały.
          limit=30
          state=${lib.escapeShellArg "${config.users.users.${cfg.user}.home}/.cache/hermes-notify"}

          # Najwyżej 3500 bajtów; gdy cięcie wypadło w środku znaku UTF-8, sed
          # (bajtowo, locale C) usuwa z końca jego niepełną sekwencję.
          text=$(head -c 3500 | LC_ALL=C sed -z -E $'s/([\xc0-\xdf]|[\xe0-\xef][\x80-\xbf]?|[\xf0-\xf7][\x80-\xbf]{0,2})$//')
          if [[ -z ''${text//[[:space:]]/} ]]; then
            echo "hermes-notify-receive: pusty tekst" >&2
            exit 1
          fi

          # Znaczniki czasu wysyłek z ostatniej godziny; flock, bo naraz mogą
          # przyjść wiadomości z tunelu, z localhost i od samego Hermesa.
          mkdir -p "$state"
          {
            flock 9
            now=$(date +%s)
            touch "$state/sent"
            mapfile -t recent < <(awk -v since="$((now - 3600))" '$1 > since' "$state/sent")
            if ((''${#recent[@]} >= limit)); then
              echo "hermes-notify-receive: wyczerpany limit $limit wiadomości na godzinę" >&2
              exit 1
            fi
            printf '%s\n' "''${recent[@]}" "$now" >"$state/sent"
          } 9>"$state/lock"

          # stderr: mautrix wypisuje przy zamykaniu nieszkodliwe tracebacki.
          # Kod wyjścia hermes send przechodzi dalej (exec).
          exec ${lib.getExe cfg.cliWrapper} send --to ${lib.escapeShellArg "matrix:${room}"} -q -f - <<<"$text" 2>/dev/null
        '';
      };

      claudeNotify = mkClaudeNotify {
        inherit pkgs receiver;
        ssh = config.programs.ssh.package;
        tmux = config.programs.tmux.package;
        key = config.age.secrets.hermes-notify-key.path;
        target = "localhost";
      };
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!enable) [
          "hermes-notify: brak modules/_secrets/hermes-notify-key.age w gicie albo MATRIX_HOME_ROOM (hermes-matrix.age, matrix.nix) — claude-notify wyłączone."
        ];
      }
      (lib.mkIf enable {
        # Klucz klienta dla nixos (grupa hermes). ssh nie odrzuca go jako
        # „too open”: tryb sprawdza tylko u właściciela pliku, a hermes
        # (właściciel) nie używa ssh, tylko woła odbiornik wprost.
        age.secrets.hermes-notify-key = {
          file = secretFile;
          owner = cfg.user;
          inherit (cfg) group;
          mode = "0440";
        };

        # Przez /etc/ssh/authorized_keys.d, nie ~/.ssh: katalog domowy hermes
        # (2770) jest zapisywalny dla grupy, więc StrictModes odrzuciłby
        # ~/.ssh/authorized_keys.
        users.users.${cfg.user}.openssh.authorizedKeys.keys = [
          ''from="127.0.0.1,::1",restrict,command="${lib.getExe receiver}" ${keys.users.hermes-notify}''
        ];

        environment = {
          systemPackages = [ claudeNotify ];
          etc = claudeCodeSettings pkgs claudeNotify;
        };
      })
    ];

  flake.modules.nixos.nixos-claude-notify =
    { config, pkgs, ... }:
    let
      claudeNotify = mkClaudeNotify {
        inherit pkgs;
        ssh = config.programs.ssh.package;
        tmux = config.programs.tmux.package;
        key = config.age.secrets.hermes-notify-key.path;
        target = "ssh.${customTop.site.full}";
        sshOptions = [
          "-o"
          "ProxyCommand=${lib.getExe pkgs.cloudflared} access ssh --hostname %h"
        ];
      };
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!hasSecret) [
          "hermes-notify: brak modules/_secrets/hermes-notify-key.age w gicie — claude-notify wyłączone."
        ];
      }
      (lib.mkIf hasSecret {
        age.secrets.hermes-notify-key = {
          file = secretFile;
          owner = config.customBot.defaultUser;
          mode = "0400";
        };

        environment = {
          systemPackages = [ claudeNotify ];
          etc = claudeCodeSettings pkgs claudeNotify;
        };
      })
    ];
}
