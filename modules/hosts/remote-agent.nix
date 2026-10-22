# Zdalny dostęp Claude Code z raspberry-pi-4 do laptopa (host nixos): konto
# claude-remote na laptopie, a na RPi `ssh laptop` i `laptop-run` do ewaluacji
# i buildów x86_64 (krok 3 weryfikacji), które na RPi trwają minuty albo są
# niewykonalne.
#
# Granica zaufania: laptop ma roota na RPi, a RPi jest wystawione do internetu
# (tunel: Nextcloud, ttyd, Hermes). Klucz z RPi NIE loguje więc na konto
# główne laptopa (sekrety agenix, ~/.ssh z kluczem roota RPi, wheel → podsłuch
# hasła sudo), tylko na osobne konto claude-remote:
# - własna grupa główna (nie `users`), żadnych grup dodatkowych (wheel, kvm,
#   systemd-journal), brak sekretów agenix; home 0700, jak konta głównego;
# - authorized_keys z `from=<LAN>` i `restrict` (bez przekierowań portów,
#   agenta, X11 i pty) — laptop nie staje się przyczółkiem do dalszej sieci;
# - trusted-users bez zmian, dlatego nie nix.buildMachines (zdalny builder
#   wymaga zaufanego użytkownika po stronie laptopa);
# - aktywacja (switch) zostaje u użytkownika (`update-local`).
# Ryzyko resztkowe: zwykłe konto lokalne widzi usługi na localhost (ollama
# :11434 bez autoryzacji) i może obciążyć CPU/dysk.
{ customTop, ... }:
let
  inherit (customTop) keys;
  user = "claude-remote";
in
{
  flake.modules.nixos.nixos-remote-agent =
    { config, ... }:
    let
      inherit (config.users.users.${user}) home homeMode;
    in
    {
      users = {
        users.${user} = {
          isNormalUser = true;
          group = user;
          description = "Claude Code z raspberry-pi-4 (eval/build, bez sudo)";
          openssh.authorizedKeys.keys = [
            ''from="${customTop.lan.subnet}",restrict ${keys.users.claude-rpi}''
          ];
        };
        groups.${user} = { };
      };

      # createHome działa w aktywacji, a ta przy starcie (`update-local-boot`
      # + reboot) biegnie przed zamontowaniem /home, więc katalog ląduje pod
      # punktem montowania; tmpfiles działa po local-fs.target. /home to
      # root:root 0755: claude-remote nie podmieni tej ścieżki na symlink.
      systemd.tmpfiles.rules = [ "d ${home} ${homeMode} ${user} ${user} - -" ];
    };

  flake.modules.nixos.rpi-remote-agent =
    { config, pkgs, ... }:
    let
      # laptop-run [CMD...]: CMD na laptopie w migawce bieżącego repo
      # (~/work/<repo>); bez CMD tylko synchronizacja. Migawka = to, co widzi
      # lokalny flake (śledzone pliki ze zmianami i nowe dodane do indeksu),
      # zbudowana na tymczasowym indeksie, więc HEAD i indeks repo zostają bez
      # zmian; na laptopie `git add -A`, żeby tamtejszy flake widział te same
      # pliki. Bez `git push`: żadnego przepisywania refów.
      laptop-run = pkgs.writeShellApplication {
        name = "laptop-run";
        # SC2029: komendy dla ssh są celowo składane lokalnie (argumenty przez %q).
        excludeShellChecks = [ "SC2029" ];
        runtimeInputs = [
          config.programs.git.package
          config.programs.ssh.package
        ];
        text = ''
          repo=$(git rev-parse --show-toplevel)
          dest=work/$(basename "$repo")
          qdest=$(printf '%q' "$dest") # do komend dla powłoki po stronie laptopa

          index=$(mktemp)
          trap 'rm -f "$index"' EXIT
          cp "$(git -C "$repo" rev-parse --path-format=absolute --git-path index)" "$index"
          GIT_INDEX_FILE=$index git -C "$repo" add -u
          tree=$(GIT_INDEX_FILE=$index git -C "$repo" write-tree)

          # Stare pliki precz (poza .git i `result` dla diff-closures), potem
          # rozpakowanie migawki i indeks = migawka.
          git -C "$repo" archive --format=tar "$tree" |
            ssh laptop "mkdir -p $qdest && cd $qdest && git init -q &&
              find . -mindepth 1 -maxdepth 1 ! -name .git ! -name result -exec rm -rf {} + &&
              tar -xf - && git add -A"

          remote="cd $qdest"
          if (($#)); then
            remote+=" && $(printf '%q ' "$@")"
          fi
          # Bez exec: trap musi jeszcze usunąć tymczasowy indeks.
          ssh laptop "$remote"
        '';
      };
    in
    {
      programs.ssh = {
        knownHosts.laptop = {
          hostNames = [ customTop.lan.laptop ];
          publicKey = keys.sshHostKeys.nixos;
        };
        extraConfig = ''
          Host laptop
            HostName ${customTop.lan.laptop}
            User ${user}
            IdentityFile ~/.ssh/id_ed25519_laptop
            IdentitiesOnly yes
            StrictHostKeyChecking yes
            ConnectTimeout 5
        '';
      };

      environment.systemPackages = [ laptop-run ];
    };
}
