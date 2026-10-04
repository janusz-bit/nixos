# Instalacja hosta nixos — paczki:
#   install-system          z live ISO: `nix run github:janusz-bit/nixos` albo
#                           `nix run .` z klonu (packages.default; na stockowym
#                           ISO: `nix --extra-experimental-features
#                           'nix-command flakes' run …`) — potrzebuje sieci
#   install-system-offline  ten sam skrypt wbudowany w ISO z iso.nix — bez sieci
#   post-install            kroki po instalacji, na nowym systemie
#
# install-system instaluje host `nixos` z tej rewizji flake'a, z której go
# uruchomiono (self) — skrypt disko i system pochodzą z niej, nie z GitHuba.
# Dysk: `--disk URZĄDZENIE` albo wybór z listy (Enter = dysk z disko.nix).
# Warianty różnią się źródłem systemu i /etc/nixos:
#   - online:  `nixos-install --flake` (ewaluacja + cache albo build),
#     /etc/nixos dostaje klon origin;
#   - offline: `nixos-install --system <toplevel>` — toplevel hosta nixos jest
#     w domknięciu skryptu, więc trafia do squashfs ISO, a nixos-install tylko
#     go kopiuje (bez ewaluacji i cache); /etc/nixos dostaje źródła flake'a
#     (self) jako świeże repo bez wspólnej historii z GitHubem.
#
# Klucze nie są potrzebne: klucze sbctl generuje limine-install
# (secureBoot.autoGenerateKeys, firmware nietknięty), a klucz agenix i wpisanie
# kluczy Secure Boot do firmware robi po instalacji post-install (z siecią —
# ewaluuje flake z /etc/nixos):
#   nix run /etc/nixos#post-install [ssh|secure-boot]   (bez argumentu: oba)
# - ssh: klucz roota /root/.ssh/id_ed25519 (age.identityPaths) + wpis
#   hosts.nixos w modules/_secrets/keys.nix. Sekrety trzeba potem przeszyfrować
#   kluczem raspberry-pi-4 (odbiorca wszystkich sekretów) — skrypt to wypisuje.
# - secure-boot: wpisanie kluczy sbctl do firmware procedurą z AGENTS.md
#   (Insyde: sbctl enroll-keys nie widzi zmiennych EFI, więc eksport .auth +
#   efi-updatevar, potem odtworzenie dbx z dbxDefault). Firmware musi być
#   w Setup Mode — Linux tego nie sprawdzi, skrypt pyta.
# Do tego czasu Secure Boot w BIOS zostaje wyłączony, a sekrety agenix się
# nie odszyfrowują.
{ self, customTop, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (self.nixosConfigurations.nixos) config;
      inherit (config.networking) hostName;
      inherit (customTop.repository) place url;
      inherit (config.disko) rootMountPoint;
      user = config.customBot.defaultUser;
      inherit (config.users.users.${user}) group;
      configuredDisk = config.disko.devices.disk.main.device;
      # Skrypt disko dla DOWOLNEGO dysku, zbudowany z góry (bez ewaluacji
      # flake'a w trakcie instalacji, więc także offline): urządzeniem jest
      # dowiązanie, które install-system tuż przed formatowaniem ustawia na
      # wybrany dysk — disk-deactivate robi realpath, a sgdisk/blkid/partprobe
      # przyjmują dowiązania jak /dev/disk/by-id/…. Instalowany system jest ten
      # sam: fileSystems i LUKS wskazują /dev/disk/by-partlabel/disk-main-*.
      diskLink = "/run/install-system/disk";
      disko =
        (self.nixosConfigurations.nixos.extendModules {
          modules = [ { disko.devices.disk.main.device = lib.mkForce diskLink; } ];
        }).config.system.build.destroyFormatMount;
      rev = self.rev or self.dirtyRev or "bez rewizji";
      sw = "/nix/var/nix/profiles/system/sw/bin";

      mkInstallSystem =
        { offline }:
        let
          usage = ''
            Użycie: install-system [--disk URZĄDZENIE]

            Instaluje host nixos (rewizja ${rev}${lib.optionalString offline ", wbudowana w ISO — bez sieci"}).
            CAŁY wybrany dysk zostanie wyczyszczony.

              --disk URZĄDZENIE  dysk docelowy, np. /dev/disk/by-id/nvme-…; bez tej opcji
                                 wybór z listy (Enter = ${configuredDisk} z disko.nix)
          '';
          # Repo dla /etc/nixos w "$work/repo", przed czyszczeniem dysku.
          prepareRepo =
            if offline then
              ''
                cp -r ${self} "$work/repo"
                chmod -R u+w "$work/repo"
                git -C "$work/repo" init -q -b master
                git -C "$work/repo" remote add origin ${lib.escapeShellArg url}
                # Śledzenie origin/master od razu (git pull/push, repo-sync) — zadziała po fetch.
                git -C "$work/repo" config branch.master.remote origin
                git -C "$work/repo" config branch.master.merge refs/heads/master
                git -C "$work/repo" add -A
                git -C "$work/repo" -c user.name=install-system -c user.email=install-system@localhost \
                  commit -q -m "install-system (offline): rewizja ${rev}"
              ''
            else
              # Klon przy okazji sprawdza dostęp do sieci, zanim dysk zostanie wyczyszczony.
              ''
                git clone ${lib.escapeShellArg url} "$work/repo"
                origin_rev="$(git -C "$work/repo" rev-parse HEAD)"
                if [[ "$origin_rev" != ${lib.escapeShellArg (self.rev or "")} ]]; then
                  echo "UWAGA: instalowana jest rewizja ${rev}, a $place dostanie origin ($origin_rev)."
                fi
              '';
          nixosInstall =
            if offline then
              ''
                nixos-install --root "$mnt" --system ${config.system.build.toplevel} \
                  --no-root-passwd --no-channel-copy
              ''
            else
              # accept-flake-config: cache z nixConfig (kernel CachyOS, llm-agents) —
              # bez nich kernel LTO kompiluje się lokalnie.
              ''
                nixos-install --root "$mnt" --flake ${lib.escapeShellArg "${self}#nixos"} \
                  --no-root-passwd --option accept-flake-config true
              '';
          repoNote = lib.optionalString offline ''
            echo "- $place: źródła rewizji ${rev} bez historii z GitHuba (origin ustawiony)."
            echo "  Po podłączeniu do sieci, przed post-install:"
            echo "  git -C $place fetch origin && git -C $place reset --hard origin/master"
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
            mnt=${lib.escapeShellArg rootMountPoint}
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

            if [[ $EUID -ne 0 ]]; then
              exec sudo "$0" "''${args[@]}"
            fi

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
            enter ${sw}/chown -R ${user}:${group} "$place"
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
            ${repoNote}
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
        install-system = mkInstallSystem { offline = false; };
        # Tylko dla ISO (iso.nix): `nix run` tej paczki ściągnąłby całe
        # domknięcie systemu (~50 GiB) do RAM live ISO.
        install-system-offline = mkInstallSystem { offline = true; };

        post-install = pkgs.writeShellApplication {
          name = "post-install";
          runtimeInputs = with pkgs; [
            efitools
            openssh
            sbctl
          ];
          text = ''
            place=${lib.escapeShellArg place}

            usage() { printf '%s' ${lib.escapeShellArg postInstallUsage}; }
            die() {
              echo "post-install: $*" >&2
              exit 1
            }
            confirm() {
              local answer
              read -r -p "$1 [t/N] " answer
              [[ "$answer" == [tT] ]]
            }

            ssh_key() {
              local key=/root/.ssh/id_ed25519
              local keys_nix="$place/modules/_secrets/keys.nix"
              local old new content
              [[ -f "$keys_nix" ]] || die "brak $keys_nix"

              if [[ -f "$key" ]]; then
                echo "$key już istnieje — nie nadpisuję."
              else
                install -d -m 0700 /root/.ssh
                ssh-keygen -q -t ed25519 -N "" -C "root@${hostName}" -f "$key"
                echo "Wygenerowano $key."
              fi
              new="$(ssh-keygen -y -f "$key" | cut -d' ' -f1-2) root@${hostName}"
              old="$(nix --extra-experimental-features nix-command eval --raw --file "$keys_nix" hosts.nixos)"

              if [[ "$(cut -d' ' -f1-2 <<<"$old")" == "$(cut -d' ' -f1-2 <<<"$new")" ]]; then
                echo "Klucz jest już odbiorcą sekretów (hosts.nixos) — agenix odszyfruje je przy update-local."
                return
              fi
              content="$(<"$keys_nix")"
              [[ "$content" == *"$old"* ]] || die "nie znalazłem klucza hosts.nixos w $keys_nix"
              printf '%s\n' "''${content/"$old"/"$new"}" >"$keys_nix"

              echo "Wpisano nowy klucz do $keys_nix (hosts.nixos). Sekrety są zaszyfrowane"
              echo "dla starego klucza — przeszyfruj je kluczem raspberry-pi-4:"
              echo "  1. tutaj:  git -C $place commit -am 'secrets: new nixos host key' && git -C $place push"
              echo "  2. na RPi: w klonie repo git pull, potem w modules/_secrets:"
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
            case "''${1:-}" in
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
              exec sudo "$0" "''${args[@]}"
            fi

            work="$(mktemp -d)"
            trap 'rm -rf "$work"' EXIT
            case "''${1:-}" in
              ssh) ssh_key ;;
              secure-boot) secure_boot ;;
              *)
                ssh_key
                echo
                secure_boot
                ;;
            esac
          '';
        };
      };
    };
}
