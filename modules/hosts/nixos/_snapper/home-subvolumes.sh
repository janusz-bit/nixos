# Każdy argument (ścieżka bezwzględna) ma być podwolumenem btrfs. Brakujący
# katalog powstaje jako podwolumen; istniejący zwykły katalog jest kopiowany
# reflinkami (bez zajmowania miejsca) do nowego podwolumenu i podmieniany.
# Kolejność kroków pozwala dokończyć przerwaną migrację przy następnym starcie.

is_subvolume() {
  [ "$(stat -f -c %T "$1")" = btrfs ] && [ "$(stat -c %i "$1")" = 256 ]
}

for dir in "$@"; do
  new="$dir.subvolume-new"
  old="$dir.subvolume-old"

  # Przerwano między `mv "$dir" "$old"` a `mv "$new" "$dir"`.
  if [ ! -e "$dir" ] && [ -d "$old" ]; then
    mv "$old" "$dir"
  fi
  # Niedokończona kopia.
  if [ -e "$new" ]; then
    rm -rf --one-file-system "$new"
  fi
  # Przerwano po podmianie, przed usunięciem starego katalogu.
  if [ -e "$old" ] && is_subvolume "$dir"; then
    rm -rf --one-file-system "$old"
  fi

  if [ ! -e "$dir" ]; then
    mkdir -p "$(dirname "$dir")"
    btrfs subvolume create "$dir"
  elif ! is_subvolume "$dir"; then
    echo "migracja $dir do podwolumenu"
    btrfs subvolume create "$new"
    cp -a --reflink=always "$dir/." "$new/"
    mv "$dir" "$old"
    mv "$new" "$dir"
    rm -rf --one-file-system "$old"
  fi
done
