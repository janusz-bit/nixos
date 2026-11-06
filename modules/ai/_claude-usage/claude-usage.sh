# Zużycie limitów subskrypcji Claude (sesja 5 h, tydzień, limity per model,
# extra usage) z endpointu, którego używa /usage w Claude Code. Token OAuth
# idzie do curla przez stdin (-H @-), nie przez argv, więc nie widać go w ps.

creds="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.credentials.json"
if [[ ! -r "$creds" ]]; then
  echo "claude-usage: brak $creds (zaloguj się: claude auth login)" >&2
  exit 1
fi

body=$(
  jq -r '"Authorization: Bearer " + .claudeAiOauth.accessToken' "$creds" |
    curl --silent --show-error --fail-with-body --max-time 15 \
      -H @- \
      -H 'anthropic-beta: oauth-2025-04-20' \
      -H 'User-Agent: claude-usage' \
      https://api.anthropic.com/api/oauth/usage
) || {
  echo "claude-usage: zapytanie nie powiodło się (wygasły token? uruchom claude, odświeży go): $body" >&2
  exit 1
}

if [[ "${1:-}" == "--json" ]]; then
  printf '%s\n' "$body"
  exit 0
fi

jq -r '
  def epoch: sub("\\.[0-9]+"; "") | sub("(\\+00:00|Z)$"; "Z") | fromdateiso8601;
  def left($t): ($t - now) as $s
    | if $s <= 0 then "now"
      else (($s / 86400) | floor) as $d | ((($s % 86400) / 3600) | floor) as $h | ((($s % 3600) / 60) | floor) as $m
        | (if $d > 0 then "\($d)d " else "" end) + "\($h)h \($m)m"
      end;
  def name: if .kind == "session" then "session (5h)"
    elif .kind == "weekly_all" then "weekly (all models)"
    elif .scope.model.display_name then "weekly (\(.scope.model.display_name) only)"
    else .kind end;
  (.limits[] | (.resets_at | epoch) as $t
    | "\(name): \(.percent)% used, resets \($t | strflocaltime("%Y-%m-%d %H:%M %Z")) (in \(left($t)))"
      + (if .severity != "normal" then " [\(.severity)]" else "" end)),
  "extra usage (paid credits): \(if .extra_usage.is_enabled then "on, \(.extra_usage.utilization // 0)% of monthly limit used" else "off" end)"
' <<<"$body"
