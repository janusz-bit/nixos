# nix-cache-push <ścieżka|installable>...: wysyła do cache'a w tailnecie
# domknięcie argumentów bez ścieżek podpisanych przez cache.nixos.org i bez
# tych, które cache już ma, podpisane kluczem z NIX_CACHE_SIGNING_KEY. Hasło
# PUT: NIX_CACHE_PUSH_PASSWORD (sekrety CI). Klucz i hasło idą do plików 0600
# (netrc), nie do linii poleceń. NIX_CACHE_URL zmienia adres (test VM).
#
# nix copy wprost do cache'a wysłałby pełne domknięcie: binary cache przyjmuje
# ścieżkę tylko wtedy, gdy ma już narinfo jej referencji. Dlatego nix copy
# pakuje i podpisuje wybrane ścieżki do lokalnego katalogu, w którym reszta
# domknięcia ma zaślepki narinfo, a curl wysyła z niego po kolei NAR i narinfo
# każdej z nich. Pominięte referencje klienci biorą z cache.nixos.org.
url="${NIX_CACHE_URL:-$NIX_CACHE_DEFAULT_URL}"
: "${NIX_CACHE_SIGNING_KEY:?brak NIX_CACHE_SIGNING_KEY}"
: "${NIX_CACHE_PUSH_PASSWORD:?brak NIX_CACHE_PUSH_PASSWORD}"

host="${url#*://}"
host="${host%%[:/]*}"

umask 077
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf '%s\n' "$NIX_CACHE_SIGNING_KEY" >"$tmp/signing-key"
printf 'machine %s login %s password %s\n' "$host" "$NIX_CACHE_USER" "$NIX_CACHE_PUSH_PASSWORD" >"$tmp/netrc"
# connect-timeout jak na hostach; stojący transfer kończy się po 2 minutach
# i wraca jako ponowiona próba.
curlOpts=(--silent --show-error --connect-timeout 5 --speed-limit 1 --speed-time 120 --retry 3)

# Wyniki do plików, nie `< <(…)`: błąd nix, jq czy curl przerywa skrypt.
nix path-info --recursive --json --json-format 1 "$@" >"$tmp/closure.json"
jq -r 'to_entries[] | select(any(.value.signatures[]?; startswith("cache.nixos.org-1:")) | not) | .key' \
  "$tmp/closure.json" >"$tmp/candidates"

: >"$tmp/missing"
while IFS= read -r path; do
  name="${path##*/}"
  code="$(curl "${curlOpts[@]}" --head --output /dev/null --write-out '%{http_code}' "$url/${name:0:32}.narinfo")"
  case "$code" in
  200) ;;
  404) printf '%s\n' "$path" >>"$tmp/missing" ;;
  *)
    echo "nix-cache-push: $url/${name:0:32}.narinfo: HTTP $code" >&2
    exit 1
    ;;
  esac
done <"$tmp/candidates"

if [[ ! -s $tmp/missing ]]; then
  echo "nix-cache-push: nothing to push"
  exit 0
fi
mapfile -t missing <"$tmp/missing"

# Zaślepki: nix copy sprawdza tylko, czy referencja ma narinfo w katalogu
# docelowym. Na RPi nie trafiają.
mkdir "$tmp/stage"
jq -j --rawfile missing "$tmp/missing" '
  ($missing | split("\n") | map({ (.): true }) | add) as $send
  | to_entries[]
  | select($send[.key] | not)
  | "\(.key | split("/") | last | .[0:32]).narinfo\u0000"
    + "StorePath: \(.key)\nURL: nar/stub\nCompression: none\n"
    + "NarHash: \(.value.narHash)\nNarSize: \(.value.narSize)\n"
    + "References: \(.value.references | map(split("/") | last) | join(" "))\n\u0000"
' "$tmp/closure.json" >"$tmp/stubs"
while IFS= read -r -d '' file && IFS= read -r -d '' body; do
  printf '%s' "$body" >"$tmp/stage/$file"
done <"$tmp/stubs"

nix copy --no-recursive --to "file://$tmp/stage?secret-key=$tmp/signing-key&compression=zstd" "${missing[@]}"

echo "nix-cache-push: ${#missing[@]} paths -> $url"
for path in "${missing[@]}"; do
  name="${path##*/}"
  narinfo="${name:0:32}.narinfo"
  nar="$(sed -n 's/^URL: //p' "$tmp/stage/$narinfo")"
  echo "copying $path"
  # NAR przed narinfo: klient nie dostanie narinfo bez NAR-a.
  curl "${curlOpts[@]}" --fail --netrc-file "$tmp/netrc" --upload-file "$tmp/stage/$nar" "$url/$nar"
  curl "${curlOpts[@]}" --fail --netrc-file "$tmp/netrc" --upload-file "$tmp/stage/$narinfo" "$url/$narinfo"
done
