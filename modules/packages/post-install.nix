# post-install — kroki po install-system, na zainstalowanym laptopie:
#   nix run /etc/nixos#post-install [ssh|secure-boot]   (bez argumentu: oba)
# - ssh: klucz roota /root/.ssh/id_ed25519 (age.identityPaths) + wpis
#   hosts.nixos w modules/_secrets/keys.nix. Sekrety trzeba potem przeszyfrować
#   kluczem raspberry-pi-4 (odbiorca wszystkich sekretów) — skrypt to wypisuje.
# - secure-boot: wpisanie kluczy sbctl do firmware procedurą z AGENTS.md
#   (Insyde: sbctl enroll-keys nie widzi zmiennych EFI, więc eksport .auth +
#   efi-updatevar, potem odtworzenie dbx z dbxDefault). Firmware musi być
#   w Setup Mode — Linux tego nie sprawdzi, skrypt pyta.
{ self, customTop, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      inherit (self.nixosConfigurations.nixos.config.networking) hostName;
      inherit (customTop.repository) place;
      usage = ''
        Użycie: post-install [ssh|secure-boot]

          ssh          klucz SSH roota dla agenix + wpis w modules/_secrets/keys.nix
          secure-boot  wpisanie kluczy Secure Boot do firmware (Setup Mode) i dbx
          bez argumentu: oba kroki po kolei
      '';
    in
    {
      packages.post-install = pkgs.writeShellApplication {
        name = "post-install";
        runtimeInputs = with pkgs; [
          efitools
          openssh
          sbctl
        ];
        text = ''
          place=${lib.escapeShellArg place}

          usage() { printf '%s' ${lib.escapeShellArg usage}; }
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
}
