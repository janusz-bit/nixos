# install-system (wariant OFFLINE) — ten sam `install-system`, ale wbudowany
# tylko w ISO z iso.nix. W przeciwieństwie do install.nix (online, git clone
# + `nixos-install --flake`) ten wariant nie dotyka sieci wcale:
#
#   - /etc/nixos dostaje kopię tej samej rewizji flake'a, z której zbudowano
#     ISO (self) — zamiast `git clone` z GitHuba. self jest już w Nix store
#     (żadnego klonowania/sieci); robimy nad tym świeży `git init` + remote
#     origin, żeby update-local/push dalej działały po podłączeniu do sieci.
#   - `nixos-install --system <gotowy closure>` (nie `--flake`): instalowany
#     jest JUŻ ZBUDOWANY `config.system.build.toplevel` hosta nixos, więc
#     nixos-install nie ewaluuje flake'a i nie pobiera nic z cache —
#     TYLKO kopiuje closure, który jest już lokalnie (bo install-offline
#     odwołuje się do niego w tekście skryptu: Nix automatycznie dolicza go
#     do zależności tego pakietu, a przez to — do squashfs ISO w iso.nix).
#   - skrypt disko jest gotowy dla dowolnego dysku (dowiązanie, patrz
#     install.nix), więc wybór dysku spoza disko.nix też nie potrzebuje sieci.
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
      # Skrypt disko dla dowolnego dysku, bez sieci — opis w install.nix.
      diskLink = "/run/install-system/disk";
      disko =
        (self.nixosConfigurations.nixos.extendModules {
          modules = [ { disko.devices.disk.main.device = lib.mkForce diskLink; } ];
        }).config.system.build.destroyFormatMount;
      rev = self.rev or self.dirtyRev or "bez rewizji";
      usage = ''
        Użycie: install-system [--disk URZĄDZENIE]

        Instaluje host nixos (rewizja ${rev}) BEZ SIECI — system jest
        wbudowany w ten ISO. CAŁY wybrany dysk zostanie wyczyszczony.

          --disk URZĄDZENIE  dysk docelowy, np. /dev/disk/by-id/nvme-…; bez tej opcji
                             wybór z listy (Enter = ${configuredDisk} z disko.nix)
      '';
    in
    {
      packages.install-system-offline = pkgs.writeShellApplication {
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

          confirm_and_wipe ${disko}

          echo "Kopiuję repo z ISO (bez sieci) do $place..."
          mkdir -p "$mnt$(dirname "$place")"
          cp -a ${self} "$mnt$place"
          chmod -R u+w "$mnt$place"
          git -C "$mnt$place" init -q -b master
          git -C "$mnt$place" remote add origin ${lib.escapeShellArg url}
          # Śledzenie origin/master od razu (git pull/push, repo-sync) — zadziała po fetch.
          git -C "$mnt$place" config branch.master.remote origin
          git -C "$mnt$place" config branch.master.merge refs/heads/master
          git -C "$mnt$place" add -A
          git -C "$mnt$place" \
            -c user.name=install-system -c user.email=install-system@localhost \
            commit -q -m "install-system (offline): rewizja ${rev}"

          echo "Instaluję system wbudowany w ISO (bez sieci)..."
          nixos-install --root "$mnt" --system ${config.system.build.toplevel} \
            --no-root-passwd --no-channel-copy

          nixos-enter --root "$mnt" --silent -- \
            /nix/var/nix/profiles/system/sw/bin/chown -R ${user}:${group} "$place"
          # initialPassword z konfiguracji (root/root, ${user}/${user}) zastępujemy od razu.
          set_passwords "$mnt" root ${user}

          echo
          echo "Instalacja zakończona (bez sieci). Secure Boot w BIOS zostaw wyłączony."
          if [[ "$disk_dev" != "$(readlink -f "$configured_disk")" ]]; then
            echo "- disko.nix: ustaw disko.devices.disk.main.device = \"$disk\""
            echo "  (modules/hosts/nixos/disko.nix) — system działa i bez tego, ale install-system"
            echo "  proponuje dysk z disko.nix."
          fi
          echo "- $place to świeży 'git init' (origin ustawiony, bez wspólnej historii z GitHubem)."
          echo "  Po podłączeniu do sieci, przed post-install: git -C $place fetch origin &&"
          echo "  git -C $place reset --hard origin/master   (ściąga prawdziwą historię repo)."
          echo "- Po uruchomieniu nowego systemu: nix run $place#post-install"
          echo "  (klucz SSH roota dla agenix, potem Secure Boot)."
        '';
      };
    };
}
