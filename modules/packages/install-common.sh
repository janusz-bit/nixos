# Wspólne funkcje dla obu wariantów install-system:
#   - install.nix          (online: `nix run github:janusz-bit/nixos`, klonuje
#                            origin, instaluje przez `nixos-install --flake`)
#   - install-offline.nix  (offline: wbudowany w ISO z iso.nix, kopiuje repo
#                            z tego samego store'a co skrypt, instaluje przez
#                            `nixos-install --system <gotowy closure>` — bez sieci)
#
# Tylko definicje funkcji — nic się nie wykonuje przy wczytaniu (`source`).
# Wywołujący musi PRZED użyciem ustawić $configured_disk, $mnt i $disk_link oraz
# zdefiniować die() i usage() (parse_disk_arg woła usage() przy -h/błędzie).

# Stabilna ścieżka /dev/disk/by-id/… dla urządzenia (jak w disko.nix).
by_id() {
  local link
  for link in /dev/disk/by-id/*; do
    case "$link" in
      *-part[0-9]* | */nvme-eui.* | */wwn-*) continue ;;
    esac
    if [[ "$(readlink -f "$link")" == "$1" ]]; then
      echo "$link"
      return
    fi
  done
  echo "$1"
}

# Ustawia $disk: wybór z listy dysków, Enter = dysk z disko.nix ($configured_disk).
choose_disk() {
  local configured="" mark name type answer i
  local -a disks=()
  if [[ -b "$configured_disk" ]]; then
    configured="$(readlink -f "$configured_disk")"
  fi
  while read -r name type; do
    if [[ "$type" == disk && "$name" != /dev/zram* ]]; then
      disks+=("$name")
    fi
  done < <(lsblk -dpno NAME,TYPE)
  ((${#disks[@]})) || die "nie znaleziono żadnego dysku"

  echo "Dyski:"
  for i in "${!disks[@]}"; do
    mark=""
    if [[ "${disks[i]}" == "$configured" ]]; then
      mark="  ← disko.nix"
    fi
    echo "  $((i + 1))) $(lsblk -dno NAME,SIZE,TRAN,MODEL,SERIAL "${disks[i]}")$mark"
  done
  while true; do
    if [[ -n "$configured" ]]; then
      read -r -p "Numer dysku [Enter = disko.nix]: " answer || die "przerwano"
      if [[ -z "$answer" ]]; then
        disk="$configured_disk"
        return
      fi
    else
      echo "Dysku z disko.nix ($configured_disk) nie ma w tym komputerze."
      read -r -p "Numer dysku: " answer || die "przerwano"
    fi
    if [[ "$answer" =~ ^[0-9]+$ ]] && ((10#$answer >= 1 && 10#$answer <= ${#disks[@]})); then
      disk="$(by_id "${disks[10#$answer - 1]}")"
      return
    fi
    echo "Nieprawidłowy numer."
  done
}

# Parsuje "$@" (--disk URZĄDZENIE / -h / --help); ustawia $disk i $args.
parse_disk_arg() {
  args=("$@")
  disk=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --disk)
        disk="${2:?brak URZĄDZENIA}"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 1
        ;;
    esac
  done
}

# Wymaga wcześniejszego parse_disk_arg (ustawia $args).
reexec_root() {
  if [[ $EUID -ne 0 ]]; then
    exec sudo "$0" "${args[@]}"
  fi
}

# Sprawdzenia PRZED czyszczeniem dysku. Wymaga $disk (parse_disk_arg) i $mnt;
# ustawia $disk_dev.
safety_checks() {
  [[ -d /sys/firmware/efi ]] || die "system nie jest uruchomiony w trybie UEFI"
  [[ -n "$disk" ]] || choose_disk
  [[ -b "$disk" ]] || die "nie ma dysku $disk"
  disk_dev="$(readlink -f "$disk")"
  while read -r mountpoint; do
    if [[ -n "$mountpoint" && "$mountpoint" != "$mnt" && "$mountpoint" != "$mnt"/* ]]; then
      die "$disk jest w użyciu ($mountpoint) — uruchom install-system z live ISO"
    fi
  done < <(lsblk -nro MOUNTPOINT "$disk")
  # disko formatuje, a initrd otwiera partycje po by-partlabel/disk-main-*:
  # te same etykiety na innym dysku (np. po starej instalacji) oznaczają
  # sformatowanie albo uruchomienie złej partycji.
  while read -r part parent label; do
    if [[ "$label" == disk-main-* && "$parent" != "$disk_dev" ]]; then
      die "$part na innym dysku ($parent) ma etykietę $label z disko.nix — odłącz ten dysk albo usuń jego etykiety"
    fi
  done < <(lsblk -rnpo NAME,PKNAME,PARTLABEL)
}

# $1 = katalog z disko-destroy-format-mount zbudowanym dla dysku $disk_link
# (dowiązanie, patrz install.nix). Wymaga $disk, $disk_dev, $disk_link.
confirm_and_wipe() {
  echo "UWAGA: install-system SKASUJE CAŁY dysk $disk ($disk_dev, $(lsblk -dno SIZE,MODEL "$disk"))."
  read -r -p "Wpisz dokładnie 'SKASUJ' aby kontynuować: " answer
  [[ "$answer" == SKASUJ ]] || die "przerwano"

  mkdir -p "$(dirname "$disk_link")"
  ln -sfn "$disk_dev" "$disk_link"
  echo "Podaj to samo hasło dla obu wolumenów LUKS (swap i crypted) — initrd zapyta wtedy raz."
  "$1/bin/disko-destroy-format-mount" --yes-wipe-all-disks
}

# Hasła root/<user> na zainstalowanym systemie (initialPassword jest tylko
# tymczasowy). $1 = mountpoint, reszta argumentów = konta.
set_passwords() {
  local mnt="$1"
  shift
  local account
  for account in "$@"; do
    echo "Hasło dla $account:"
    until nixos-enter --root "$mnt" --silent -- /nix/var/nix/profiles/system/sw/bin/passwd "$account"; do
      echo "Spróbuj ponownie."
    done
  done
}
