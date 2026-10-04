# install-system (`nix run github:janusz-bit/nixos` albo `nix run .` z klonu;
# na live ISO NixOS flakes są wyłączone: `nix --extra-experimental-features
# 'nix-command flakes' run …`). Instaluje host `nixos` z tej rewizji flake'a,
# z której uruchomiono skrypt (self) — skrypt disko i system pochodzą z niej,
# nie z GitHuba. /etc/nixos dostaje klon origin. Dysk: `--disk URZĄDZENIE`
# albo wybór z listy (Enter = dysk z disko.nix).
#
# Ten wariant POTRZEBUJE SIECI: git clone origin + `nixos-install --flake`
# (ewaluacja flake'a + pull z cache albo build). Wariant w pełni offline (bez
# sieci — wbudowany w ISO z iso.nix) to install-offline.nix.
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
      # Skrypt disko dla DOWOLNEGO dysku, zbudowany z góry (bez ewaluacji
      # flake'a w trakcie instalacji, więc także offline): urządzeniem jest
      # dowiązanie, które confirm_and_wipe (install-common.sh) ustawia na
      # wybrany dysk — disk-deactivate robi realpath, a sgdisk/blkid/partprobe
      # przyjmują dowiązania jak /dev/disk/by-id/…. Instalowany system jest ten
      # sam: fileSystems i LUKS wskazują /dev/disk/by-partlabel/disk-main-*.
      diskLink = "/run/install-system/disk";
      disko =
        (self.nixosConfigurations.nixos.extendModules {
          modules = [ { disko.devices.disk.main.device = lib.mkForce diskLink; } ];
        }).config.system.build.destroyFormatMount;
      rev = self.rev or self.dirtyRev or "bez rewizji";
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
        text = builtins.readFile ./install-common.sh + ''

          configured_disk=${lib.escapeShellArg configuredDisk}
          mnt=${lib.escapeShellArg rootMountPoint}
          place=${lib.escapeShellArg place}
          disk_link=${lib.escapeShellArg diskLink}

          usage() { printf '%s' ${lib.escapeShellArg usage}; }
          die() {
            echo "install-system: $*" >&2
            exit 1
          }

          parse_disk_arg "$@"
          reexec_root

          # Wszystko, co może się nie udać, sprawdzamy PRZED czyszczeniem dysku.
          safety_checks

          # Klon przed czyszczeniem dysku — przy okazji sprawdza dostęp do sieci.
          work="$(mktemp -d)"
          trap 'rm -rf "$work"' EXIT
          git clone ${lib.escapeShellArg url} "$work/repo"
          origin_rev="$(git -C "$work/repo" rev-parse HEAD)"
          if [[ "$origin_rev" != ${lib.escapeShellArg (self.rev or "")} ]]; then
            echo "UWAGA: instalowana jest rewizja ${rev}, a $place dostanie origin ($origin_rev)."
          fi

          confirm_and_wipe ${disko}

          mkdir -p "$mnt$(dirname "$place")"
          cp -a "$work/repo" "$mnt$place"

          # accept-flake-config: cache z nixConfig (kernel CachyOS, llm-agents) —
          # bez nich kernel LTO kompiluje się lokalnie.
          nixos-install --root "$mnt" --flake ${lib.escapeShellArg "${self}#nixos"} \
            --no-root-passwd --option accept-flake-config true

          nixos-enter --root "$mnt" --silent -- \
            /nix/var/nix/profiles/system/sw/bin/chown -R ${user}:${group} "$place"
          # initialPassword z konfiguracji (root/root, ${user}/${user}) zastępujemy od razu.
          set_passwords "$mnt" root ${user}

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
