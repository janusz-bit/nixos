# nix-cache-push <ścieżka|installable>...: wysyła do cache'a w tailnecie
# domknięcie argumentów bez ścieżek podpisanych przez cache.nixos.org,
# podpisane kluczem z NIX_CACHE_SIGNING_KEY. Hasło PUT: NIX_CACHE_PUSH_PASSWORD
# (sekrety CI). Klucz i hasło idą do plików 0600 (netrc), nie do linii
# poleceń. NIX_CACHE_URL zmienia adres (test VM).
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

# Podstawienie, nie `< <(…)`: błąd nix path-info przerywa skrypt zamiast
# dać pustą listę.
paths="$(
  nix path-info --recursive --json --json-format 1 "$@" |
    jq -r 'to_entries[] | select(any(.value.signatures[]?; startswith("cache.nixos.org-1:")) | not) | .key'
)"
if [[ -z $paths ]]; then
  echo "nix-cache-push: nothing to push"
  exit 0
fi
mapfile -t pathList <<<"$paths"

echo "nix-cache-push: ${#pathList[@]} paths -> $url"
nix copy --netrc-file "$tmp/netrc" \
  --to "$url?secret-key=$tmp/signing-key&compression=zstd" \
  "${pathList[@]}"
