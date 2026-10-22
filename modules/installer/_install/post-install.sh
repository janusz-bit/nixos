die() {
  echo "post-install: $*" >&2
  exit 1
}
confirm() {
  local answer
  read -r -p "$1 [t/N] " answer
  [[ "$answer" == [tT] ]]
}

keys_nix="$place/modules/_secrets/keys.nix"

# set_key ATTR KLUCZ — wpisuje KLUCZ do keys.nix pod ATTR, gdy się
# różni (porównanie bez komentarza), po potwierdzeniu. Kod 0: plik
# zmieniony albo brak wpisu (wypisuje linię do dopisania), 1: wpis
# aktualny. Wołane w `if`, więc errexit wewnątrz nie działa —
# stąd jawna kontrola formatu klucza.
set_key() {
  local attr=$1 new=$2 old content
  local key_re='^ssh-ed25519 [A-Za-z0-9+/]+=*( .*)?$'
  [[ $new =~ $key_re ]] || die "nieprawidłowy klucz dla $attr: '$new'"
  if ! old="$(nix --extra-experimental-features nix-command eval --raw --file "$keys_nix" "$attr" 2>/dev/null)"; then
    echo "Brak wpisu $attr w $keys_nix — dopisz w sekcji ${attr%%.*}:"
    echo "  ${attr#*.} = \"$new\";"
    return 0
  fi
  [[ "$(cut -d' ' -f1-2 <<<"$old")" != "$(cut -d' ' -f1-2 <<<"$new")" ]] || return 1
  content="$(<"$keys_nix")"
  [[ "$content" == *"$old"* ]] || die "nie znalazłem klucza $attr w $keys_nix"
  echo "$attr w $keys_nix:"
  echo "  stary: $old"
  echo "  nowy:  $new"
  confirm "Zastąpić?" || die "przerwano: $attr bez zmian"
  printf '%s\n' "${content/"$old"/"$new"}" >"$keys_nix"
  echo "Wpisano nowy klucz do $keys_nix ($attr)."
}

ssh_key() {
  local key=/root/.ssh/id_ed25519
  # Nazwa z działającego systemu, nie z flake'a: post-install może
  # ruszyć na dowolnym hoście, a wpisy keys.nix są per host.
  local host host_key root_key
  host="$(uname -n)"
  [[ -f "$keys_nix" ]] || die "brak $keys_nix"

  if [[ -f "$key" ]]; then
    echo "$key już istnieje — nie nadpisuję."
  else
    install -d -m 0700 /root/.ssh
    ssh-keygen -q -t ed25519 -N "" -C "root@$host" -f "$key"
    echo "Wygenerowano $key."
  fi

  # Poza `if`: błąd odczytu klucza przerywa skrypt (errexit, pipefail).
  host_key="$(cut -d' ' -f1-2 /etc/ssh/ssh_host_ed25519_key.pub)"
  root_key="$(ssh-keygen -y -f "$key" | cut -d' ' -f1-2)"

  # Klucz hosta sshd przypinają known_hosts innych hostów; po
  # reinstalacji jest nowy.
  if set_key "sshHostKeys.$host" "$host_key"; then
    echo "Klucz hosta sshd nowy albo zmieniony: po wpisaniu, commicie i pushu zrób"
    echo "update na hostach, które go przypinają (nixos przypina raspberry-pi-4:"
    echo "claude-notify; raspberry-pi-4 przypina nixos: laptop-run)."
  fi

  if ! set_key "hosts.$host" "$root_key root@$host"; then
    echo "Klucz roota jest już odbiorcą sekretów (hosts.$host) — agenix odszyfruje je przy update-local."
    return
  fi
  echo "Sekrety nie są zaszyfrowane dla tego klucza — przeszyfruj je na hoście,"
  echo "który już je odszyfrowuje (laptop nixos albo raspberry-pi-4); nowy host"
  echo "dopisz najpierw do odbiorców w modules/_secrets/secrets.nix:"
  echo "  1. tutaj:  git -C $place commit -am 'secrets: new $host host key' && git -C $place push"
  echo "  2. tam:    w klonie repo git pull, potem w modules/_secrets:"
  echo "             sudo agenix -r -i /root/.ssh/id_ed25519, commit i push"
  echo "  3. tutaj:  git -C $place pull && update-local"
}

secure_boot() {
  local efivars=/sys/firmware/efi/efivars
  local dbx_default="$efivars/dbxDefault-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  local kek=/var/lib/sbctl/keys/KEK
  [[ -d "$efivars" ]] || die "system nie jest uruchomiony w trybie UEFI"

  # Zwykle klucze wygenerował już limine-install (autoGenerateKeys).
  if [[ ! -f /var/lib/sbctl/keys/db/db.key ]]; then
    sbctl create-keys
    # limine-install podpisuje limine kluczem db przy każdej instalacji.
    /run/current-system/bin/switch-to-configuration boot
  fi

  echo "Firmware Insyde ukrywa tryb Secure Boot przed Linuksem. W BIOS przełącz"
  echo "Secure Boot w Setup Mode (\"Reset to Setup Mode\" / \"Erase all Secure Boot"
  echo "settings\"; czyści to też dbx, które skrypt odtwarza z dbxDefault)."
  if ! confirm "Firmware jest w Setup Mode — wpisać klucze?"; then
    echo "Pominięto. Później: nix run $place#post-install secure-boot"
    return
  fi

  cd "$work"
  sbctl enroll-keys --microsoft --firmware-builtin=db,KEK --export auth
  efi-updatevar -f db.auth db
  efi-updatevar -f KEK.auth KEK
  # PK na końcu — jego wpisanie kończy Setup Mode.
  efi-updatevar -f PK.auth PK
  if [[ -f "$dbx_default" ]]; then
    # Pierwsze 4 bajty pliku w efivarfs to atrybuty zmiennej.
    tail -c +5 "$dbx_default" >dbx.esl
    sign-efi-sig-list -a -k "$kek/KEK.key" -c "$kek/KEK.pem" dbx dbx.esl dbx.auth
    efi-updatevar -a -f dbx.auth dbx
  else
    echo "UWAGA: brak $dbx_default — dbx zostaje puste."
  fi

  echo "Klucze wpisane. Zrestartuj, włącz Secure Boot w BIOS i sprawdź:"
  echo "  journalctl -k -b | grep -i 'secure boot'"
  echo "Zrób kopię /var/lib/sbctl — bez niej reinstalacja wymaga ponownego wpisania kluczy."
}

args=("$@")
case "${1:-}" in
  "" | ssh | secure-boot) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
if [[ $EUID -ne 0 ]]; then
  exec sudo "$0" "${args[@]}"
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
case "${1:-}" in
  ssh) ssh_key ;;
  secure-boot) secure_boot ;;
  *)
    ssh_key
    echo
    secure_boot
    ;;
esac
