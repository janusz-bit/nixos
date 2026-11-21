# nix-cache-gc: usuwa z NIX_CACHE_DIR narinfo starsze niż RETENTION_DAYS dni.
# Najpierw NAR-y, do których nie prowadzi żaden narinfo (starsze niż doba, bo
# nix wysyła NAR przed narinfo), dopiero potem stare narinfo: ich NAR-y znikają
# w następnym przebiegu, więc klient, który zdążył pobrać narinfo, dostanie
# jeszcze NAR.
: "${NIX_CACHE_DIR:?}" "${RETENTION_DAYS:?}"
export LC_ALL=C
cd "$NIX_CACHE_DIR"

if [[ -d nar ]]; then
  # Podstawienie: błąd odczytu narinfo przerywa skrypt, zamiast uznać
  # wszystkie NAR-y za osierocone.
  referenced="$(find . -maxdepth 1 -name '*.narinfo' -exec sed -n 's/^URL: //p' {} + | sort -u)"
  comm -23 <(find nar -type f -mmin +1440 | sort) <(printf '%s\n' "$referenced") |
    xargs -r -d '\n' rm -f --
fi

find . -maxdepth 1 -name '*.narinfo' -mtime +"$RETENTION_DAYS" -delete
