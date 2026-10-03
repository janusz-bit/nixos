# install-system (`nix run github:janusz-bit/nixos` albo `nix run .` z klonu;
# na live ISO NixOS flakes są wyłączone: `nix --extra-experimental-features
# 'nix-command flakes' run …`). Instaluje host `nixos` z tej rewizji flake'a,
# z której uruchomiono skrypt (self) — skrypt disko i system pochodzą z niej,
# nie z GitHuba. /etc/nixos dostaje klon origin. Dysk: `--disk URZĄDZENIE`
# albo wybór z listy (Enter = dysk z disko.nix).
#
# Klucze nie są potrzebne: klucze sbctl generuje limine-install
# (secureBoot.autoGenerateKeys, firmware nietknięty), a klucz agenix i wpisanie
# kluczy Secure Boot do firmware robi po instalacji `post-install`
# (modules/packages/post-install.nix). Do tego czasu Secure Boot w BIOS
# zostaje wyłączony, a sekrety agenix się nie odszyfrowują.
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
      sw = "/nix/var/nix/profiles/system/sw/bin";
      usage = ''
        Użycie: install-system [--disk URZĄDZENIE]

        Instaluje host nixos (rewizja ${rev}). CAŁY wybrany dysk zostanie wyczyszczony.

          --disk URZĄDZENIE  dysk docelowy, np. /dev/disk/by-id/nvme-…; bez tej opcji
                             wybór z listy (Enter = ${configuredDisk} z disko.nix)
      '';
    in
    {
      packages.install-system = pkgs.writeShellApplication {
        name = "install-system";
        runtimeInputs = with pkgs; [
          git
          nixos-install-tools
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

          if [[ "$disk_dev" == "$(readlink -f "$configured_disk")" ]]; then
            disko=${config.system.build.destroyFormatMount}
          else
            echo "Dysk spoza disko.nix — buduję skrypt disko dla $disk."
            disko="$(nix-build --no-out-link --extra-experimental-features flakes \
              ${diskoForDisk} --argstr disk "$disk")"
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
          echo "Instalacja zakończona. Secure Boot w BIOS zostaw wyłączony."
          if [[ "$disk_dev" != "$(readlink -f "$configured_disk")" ]]; then
            echo "- disko.nix: ustaw disko.devices.disk.main.device = \"$disk\""
            echo "  (modules/hosts/nixos/disko.nix) — system działa i bez tego, ale install-system"
            echo "  proponuje dysk z disko.nix."
          fi
          echo "- Po uruchomieniu nowego systemu: nix run $place#post-install"
          echo "  (klucz SSH roota dla agenix, potem Secure Boot)."
        '';
      };
    };
}
