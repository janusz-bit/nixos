# install-system (`nix run github:janusz-bit/nixos` albo `nix run .` z klonu;
# na live ISO NixOS flakes są wyłączone: `nix --extra-experimental-features
# 'nix-command flakes' run …`). Instaluje host `nixos` z tej rewizji flake'a,
# z której uruchomiono skrypt (self) — skrypt disko i system pochodzą z niej,
# nie z GitHuba. /etc/nixos dostaje klon origin. Dysk: `--disk URZĄDZENIE`
# albo wybór z listy (Enter = dysk z disko.nix).
#
# Czyszczony dysk zawiera jedyne kopie dwóch rzeczy, których nie odtworzy się
# z repo — przed reinstalacją skopiuj je, np. na pendrive:
#   sudo cp -a /var/lib/sbctl /root/.ssh/id_ed25519 /media/kopia/
#   nix run . -- --sbctl-keys /media/kopia/sbctl --age-key /media/kopia/id_ed25519
# - /var/lib/sbctl: klucze PK/KEK/db wpisane do firmware (secureBoot.enable).
#   Bez kluczy limine-install przerywa nixos-install („no sbctl secure boot
#   keys”), a nowe klucze trzeba wpisać do firmware procedurą z AGENTS.md.
# - /root/.ssh/id_ed25519: tożsamość agenix (age.identityPaths), odbiorca
#   hosts.nixos w modules/_secrets/keys.nix.
{ self, customTop, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (self.nixosConfigurations.nixos) config;
      inherit (customTop.repository) place url;
      inherit (config.disko) rootMountPoint;
      user = config.customBot.defaultUser;
      inherit (config.users.users.${user}) group;
      configuredDisk = config.disko.devices.disk.main.device;
      # Skrypt disko dla dysku innego niż w disko.nix — ten sam mechanizm co
      # `disko-install --disk main …` (extendModules z nadpisanym device).
      # Instalowany system jest ten sam: fileSystems i LUKS wskazują
      # /dev/disk/by-partlabel/disk-main-*, nie ścieżkę dysku.
      diskoForDisk = pkgs.writeText "disko-for-disk.nix" ''
        { disk }:
        let
          system = (builtins.getFlake "${self}").nixosConfigurations.nixos;
        in
        (system.extendModules {
          modules = [ { disko.devices.disk.main.device = system.pkgs.lib.mkForce disk; } ];
        }).config.system.build.destroyFormatMount
      '';
      rev = self.rev or self.dirtyRev or "bez rewizji";
      agePubKey = (import (customTop.secretsDir + "/keys.nix")).hosts.nixos;
      # "typ klucz" bez komentarza — do porównania z `ssh-keygen -y`.
      agePubKeyBody = lib.concatStringsSep " " (lib.take 2 (lib.splitString " " agePubKey));
      sw = "/nix/var/nix/profiles/system/sw/bin";
      usage = ''
        Użycie: install-system [--disk URZĄDZENIE] [--sbctl-keys KATALOG] [--age-key PLIK]

        Instaluje host nixos (rewizja ${rev}). CAŁY wybrany dysk zostanie wyczyszczony.

          --disk URZĄDZENIE     dysk docelowy, np. /dev/disk/by-id/nvme-…; bez tej opcji
                                wybór z listy (Enter = ${configuredDisk} z disko.nix)
          --sbctl-keys KATALOG  kopia /var/lib/sbctl (klucze Secure Boot z firmware);
                                bez niej generowane są nowe klucze
          --age-key PLIK        kopia /root/.ssh/id_ed25519 (klucz agenix)
      '';
    in
    {
      packages.install-system = pkgs.writeShellApplication {
        name = "install-system";
        runtimeInputs = with pkgs; [
          git
          nixos-install-tools
          openssh
          sbctl
          util-linux
        ];
        text = ''
          configured_disk=${lib.escapeShellArg configuredDisk}
          mnt=${lib.escapeShellArg rootMountPoint}
          place=${lib.escapeShellArg place}

          usage() { printf '%s' ${lib.escapeShellArg usage}; }
          die() {
            echo "install-system: $*" >&2
            exit 1
          }
          confirm() {
            local answer
            read -r -p "$1 [t/N] " answer
            [[ "$answer" == [tT] ]]
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
          sbctl_keys=""
          new_keys=""
          age_key=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --disk)
                disk="''${2:?brak URZĄDZENIA}"
                shift 2
                ;;
              --sbctl-keys)
                sbctl_keys="$(realpath "''${2:?brak KATALOGU}")"
                shift 2
                ;;
              --age-key)
                age_key="$(realpath "''${2:?brak PLIKU}")"
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

          if [[ "$disk_dev" == "$(readlink -f "$configured_disk")" ]]; then
            disko=${config.system.build.destroyFormatMount}
          else
            echo "Dysk spoza disko.nix — buduję skrypt disko dla $disk."
            disko="$(nix-build --no-out-link --extra-experimental-features flakes \
              ${diskoForDisk} --argstr disk "$disk")"
          fi

          if [[ -n "$sbctl_keys" ]]; then
            [[ -f "$sbctl_keys/GUID" && -f "$sbctl_keys/keys/db/db.key" ]] ||
              die "$sbctl_keys nie jest kopią /var/lib/sbctl (brak GUID lub keys/db/db.key)"
          else
            echo "Brak --sbctl-keys: zostaną wygenerowane NOWE klucze Secure Boot. Firmware ma"
            echo "wpisane stare, więc do czasu wpisania nowych (AGENTS.md) Secure Boot musi być wyłączony."
            confirm "Kontynuować z nowymi kluczami?" || die "przerwano"
            new_keys=1
          fi

          if [[ -n "$age_key" ]]; then
            pub="$(ssh-keygen -y -f "$age_key")" || die "nie da się odczytać klucza $age_key"
            [[ "$(cut -d' ' -f1-2 <<<"$pub")" == ${lib.escapeShellArg agePubKeyBody} ]] ||
              die "$age_key nie jest kluczem hosts.nixos z modules/_secrets/keys.nix"
          else
            echo "Brak --age-key: agenix nie odszyfruje żadnego sekretu, dopóki nie wgrasz"
            echo "/root/.ssh/id_ed25519 (odbiorca hosts.nixos w modules/_secrets/keys.nix)."
            confirm "Kontynuować bez klucza agenix?" || die "przerwano"
          fi

          work="$(mktemp -d)"
          trap 'rm -rf "$work"' EXIT
          git clone ${lib.escapeShellArg url} "$work/repo"
          origin_rev="$(git -C "$work/repo" rev-parse HEAD)"
          if [[ "$origin_rev" != ${lib.escapeShellArg (self.rev or "")} ]]; then
            echo "UWAGA: instalowana jest rewizja ${rev}, a $place dostanie origin ($origin_rev)."
          fi

          echo "UWAGA: install-system SKASUJE CAŁY dysk $disk ($disk_dev, $(lsblk -dno SIZE,MODEL "$disk"))."
          read -r -p "Wpisz dokładnie 'SKASUJ' aby kontynuować: " answer
          [[ "$answer" == SKASUJ ]] || die "przerwano"

          echo "Podaj to samo hasło dla obu wolumenów LUKS (swap i crypted) — initrd zapyta wtedy raz."
          "$disko/bin/disko-destroy-format-mount" --yes-wipe-all-disks

          mkdir -p "$mnt$(dirname "$place")"
          cp -a "$work/repo" "$mnt$place"

          if [[ -n "$new_keys" ]]; then
            # Domyślne ścieżki sbctl na live ISO, potem kopia jak przy przywracaniu.
            sbctl create-keys
            sbctl_keys=/var/lib/sbctl
          fi
          install -d -m 0755 "$mnt/var/lib/sbctl"
          cp -a "$sbctl_keys/." "$mnt/var/lib/sbctl/"
          chown -R root:root "$mnt/var/lib/sbctl"
          chmod -R go= "$mnt/var/lib/sbctl/keys"

          if [[ -n "$age_key" ]]; then
            install -d -m 0700 "$mnt/root" "$mnt/root/.ssh"
            install -m 0600 "$age_key" "$mnt/root/.ssh/id_ed25519"
            echo ${lib.escapeShellArg agePubKey} >"$mnt/root/.ssh/id_ed25519.pub"
          fi

          # accept-flake-config: cache z nixConfig (kernel CachyOS, llm-agents) —
          # bez nich kernel LTO kompiluje się lokalnie.
          nixos-install --root "$mnt" --flake ${lib.escapeShellArg "${self}#nixos"} \
            --no-root-passwd --option accept-flake-config true

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
          echo "Instalacja zakończona."
          if [[ "$disk_dev" != "$(readlink -f "$configured_disk")" ]]; then
            echo "- disko.nix: ustaw disko.devices.disk.main.device = \"$disk\""
            echo "  (modules/hosts/nixos/disko.nix) — system działa i bez tego, ale install-system"
            echo "  proponuje dysk z disko.nix."
          fi
          if [[ -n "$age_key" ]]; then
            echo "- agenix: klucz przywrócony."
          else
            echo "- agenix: wgraj /root/.ssh/id_ed25519 albo wygeneruj nowy, wpisz go do keys.nix"
            echo "  i przeszyfruj sekrety (agenix -r) kluczem innego odbiorcy."
          fi
          if [[ -n "$new_keys" ]]; then
            echo "- Secure Boot: NOWE klucze w /var/lib/sbctl — wpisz je do firmware i odtwórz dbx"
            echo "  (AGENTS.md), dopiero potem włącz Secure Boot. Zrób kopię /var/lib/sbctl."
          else
            echo "- Secure Boot: klucze przywrócone — włącz Secure Boot w firmware, jeśli był wyłączony dla ISO."
          fi
        '';
      };
    };
}
