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
