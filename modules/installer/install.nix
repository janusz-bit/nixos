# Instalacja hosta nixos: install-system (z live ISO, z siecią) i post-install
# (kroki na nowym systemie).
#
# Paczki:
#   install-system          z live ISO: `nix run github:janusz-bit/nixos` albo
#                           `nix run .` z klonu (packages.default; na stockowym
#                           ISO: `nix --extra-experimental-features
#                           'nix-command flakes' run …`) — potrzebuje sieci
#   post-install            kroki po instalacji, na nowym systemie
#
# install-system instaluje host `nixos` z rewizji flake'a, z której go
# uruchomiono (self), na dysk z `--disk` albo wybrany z listy (Enter = dysk
# z disko.nix): `nixos-install --flake`, /etc/nixos = klon origin.
#
# Klucze nie są potrzebne: klucze sbctl generuje limine-install
# (secureBoot.autoGenerateKeys, firmware nietknięty), a klucz agenix i wpisanie
# kluczy do firmware (Insyde: eksport .auth + efi-updatevar i odtworzenie dbx,
# bo sbctl enroll-keys nie widzi zmiennych EFI) robi post-install, z siecią.
# Do tego czasu Secure Boot w BIOS zostaje wyłączony, a sekrety agenix się
# nie odszyfrowują.
{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      # Host instalowany przez install-system.
      installHost = "nixos";
      host = self.nixosConfigurations.${installHost};
      inherit (host) config;
      inherit (config.customTop.repository) url;
      # Nazwa jak zmienna $place w skryptach (też _install/post-install.sh).
      place = config.customTop.repository.path;
      user = config.customBot.defaultUser;
      configuredDisk = config.disko.devices.disk.main.device;
      # Skrypt disko zbudowany z góry (bez ewaluacji w trakcie instalacji) dla
      # dowiązania, które install-system tuż przed formatowaniem ustawia na
      # wybrany dysk: disk-deactivate robi realpath, a sgdisk/blkid/partprobe
      # przyjmują dowiązania. Zainstalowany system jest ten sam, bo fileSystems
      # i LUKS wskazują /dev/disk/by-partlabel/disk-main-*.
      diskLink = "/run/install-system/disk";
      disko =
        (host.extendModules {
          modules = [ { disko.devices.disk.main.device = lib.mkForce diskLink; } ];
        }).config.system.build.destroyFormatMount;
      rev = self.rev or self.dirtyRev or "bez rewizji";
      sw = "/nix/var/nix/profiles/system/sw/bin";

      installSystem =
        let
          usage = ''
            Użycie: install-system [--disk URZĄDZENIE]

            Instaluje host nixos (rewizja ${rev}).
            CAŁY wybrany dysk zostanie wyczyszczony.

              --disk URZĄDZENIE  dysk docelowy, np. /dev/disk/by-id/nvme-…; bez tej opcji
                                 wybór z listy (Enter = ${configuredDisk} z disko.nix)
          '';
          # Repo dla /etc/nixos w "$work/repo", przed czyszczeniem dysku. Klon przy
          # okazji sprawdza dostęp do sieci, zanim dysk zostanie wyczyszczony.
          prepareRepo = ''
            git clone ${lib.escapeShellArg url} "$work/repo"
            origin_rev="$(git -C "$work/repo" rev-parse HEAD)"
            if [[ "$origin_rev" != ${lib.escapeShellArg (self.rev or "")} ]]; then
              echo "UWAGA: instalowana jest rewizja ${rev}, a $place dostanie origin ($origin_rev)."
            fi
          '';
          nixosInstall =
            # accept-flake-config: własny cachix z nixConfig, jedyny cache, który
            # może mieć kernel CachyOS (CI cachyos-kernel-update); bez niego
            # kernel kompiluje się lokalnie.
            ''
              nixos-install --root "$mnt" --flake ${lib.escapeShellArg "${self}#${installHost}"} \
                --no-root-passwd --option accept-flake-config true
            '';
        in
        pkgs.writeShellApplication {
          name = "install-system";
          runtimeInputs = with pkgs; [
            git
            nixos-install-tools
            util-linux
          ];
          text = ''
            configured_disk=${lib.escapeShellArg configuredDisk}
            disk_link=${lib.escapeShellArg diskLink}
            mnt=${lib.escapeShellArg config.disko.rootMountPoint}
            place=${lib.escapeShellArg place}

            usage() { printf '%s' ${lib.escapeShellArg usage}; }
            die() {
              echo "install-system: $*" >&2
              exit 1
            }

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

            # Ustawia $disk: wybór z listy dysków, Enter = dysk z disko.nix.
            choose_disk() {
              local configured="" mark name type answer i disks=()
              if [[ -b "$configured_disk" ]]; then
                configured="$(readlink -f "$configured_disk")"
              fi
              while read -r name type; do
                if [[ "$type" == disk && "$name" != /dev/zram* ]]; then
                  disks+=("$name")
                fi
              done < <(lsblk -dpno NAME,TYPE)
              ((''${#disks[@]})) || die "nie znaleziono żadnego dysku"

              echo "Dyski:"
              for i in "''${!disks[@]}"; do
                mark=""
                if [[ "''${disks[i]}" == "$configured" ]]; then
                  mark="  ← disko.nix"
                fi
                echo "  $((i + 1))) $(lsblk -dno NAME,SIZE,TRAN,MODEL,SERIAL "''${disks[i]}")$mark"
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
                if [[ "$answer" =~ ^[0-9]+$ ]] && ((10#$answer >= 1 && 10#$answer <= ''${#disks[@]})); then
                  disk="$(by_id "''${disks[10#$answer - 1]}")"
                  return
                fi
                echo "Nieprawidłowy numer."
              done
            }

            args=("$@")
            disk=""
            while [[ $# -gt 0 ]]; do
              case "$1" in
                --disk)
                  disk="''${2:?brak URZĄDZENIA}"
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

            [[ $EUID -eq 0 ]] || exec sudo "$0" "''${args[@]}"

            # Wszystko, co może się nie udać, sprawdzamy PRZED czyszczeniem dysku.
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

            work="$(mktemp -d)"
            trap 'rm -rf "$work"' EXIT
            ${prepareRepo}

            echo "UWAGA: install-system SKASUJE CAŁY dysk $disk ($disk_dev, $(lsblk -dno SIZE,MODEL "$disk"))."
            read -r -p "Wpisz dokładnie 'SKASUJ' aby kontynuować: " answer
            [[ "$answer" == SKASUJ ]] || die "przerwano"

            mkdir -p "$(dirname "$disk_link")"
            ln -sfn "$disk_dev" "$disk_link"
            echo "Podaj to samo hasło dla obu wolumenów LUKS (swap i crypted) — initrd zapyta wtedy raz."
            ${disko}/bin/disko-destroy-format-mount --yes-wipe-all-disks

            mkdir -p "$mnt$(dirname "$place")"
            cp -a "$work/repo" "$mnt$place"

            ${nixosInstall}

            enter() { nixos-enter --root "$mnt" --silent -- "$@"; }
            enter ${sw}/chown -R ${user}:${config.users.users.${user}.group} "$place"
            # initialPassword z konfiguracji (root/root, ${user}/${user}) zastępujemy od razu.
            for account in root ${user}; do
              echo "Hasło dla $account:"
              until enter ${sw}/passwd "$account"; do
                echo "Spróbuj ponownie."
              done
            done

            echo
            echo "Instalacja zakończona. Secure Boot w BIOS zostaw wyłączony."
            if [[ "$disk_dev" != "$(readlink -f "$configured_disk")" ]]; then
              echo "- disko.nix: ustaw disko.devices.disk.main.device = \"$disk\""
              echo "  (modules/hosts/nixos/disko.nix) — system działa i bez tego, ale install-system"
              echo "  proponuje dysk z disko.nix."
            fi
            echo "- Po uruchomieniu nowego systemu, z siecią: nix run $place#post-install"
            echo "  (klucz SSH roota dla agenix, potem Secure Boot)."
          '';
        };

      postInstallUsage = ''
        Użycie: post-install [ssh|secure-boot]

          ssh          klucz SSH roota dla agenix + wpis w modules/_secrets/keys.nix
          secure-boot  wpisanie kluczy Secure Boot do firmware (Setup Mode) i dbx
          bez argumentu: oba kroki po kolei
      '';
    in
    {
      packages = {
        install-system = installSystem;

        post-install = pkgs.writeShellApplication {
          name = "post-install";
          runtimeInputs = with pkgs; [
            coreutils
            efitools
            openssh
            sbctl
          ];
          text = ''
            place=${lib.escapeShellArg place}

            usage() { printf '%s' ${lib.escapeShellArg postInstallUsage}; }
          ''
          # post-install.sh nie definiuje place ani usage, tylko używa tych
          # z prefiksu wyżej.
          + builtins.readFile ./_install/post-install.sh;
        };
      };
    };
}
