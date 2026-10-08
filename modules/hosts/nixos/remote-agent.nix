# Zdalny dostęp Claude Code z raspberry-pi-4 do laptopa (host nixos).
#
# Po co: ewaluacja i buildy x86_64 na laptopie. Na RPi ewaluacja hosta nixos
# trwa minuty, a `nixos-rebuild build .#nixos` + diff-closures są tam
# niewykonalne (krok 3 weryfikacji z AGENTS.md).
#
# Granica zaufania: laptop ma roota na RPi, a RPi jest wystawione do internetu
# (tunel: Nextcloud, Open WebUI, ttyd, Hermes). Klucz z RPi NIE loguje więc na
# dinosaura (sekrety agenix, ~/.ssh z kluczem roota RPi, wheel → podsłuch hasła
# sudo), tylko na osobne konto claude-remote:
# - własna grupa główna (nie `users`), żadnych grup dodatkowych (wheel, kvm,
#   systemd-journal), brak sekretów agenix; home 0700 (dinosaura też 0700);
# - authorized_keys z `from=<LAN>` i `restrict` (bez przekierowań portów,
#   agenta, X11 i pty) — laptop nie staje się przyczółkiem do dalszej sieci;
# - trusted-users bez zmian, dlatego nie nix.buildMachines (zdalny builder
#   wymaga zaufanego użytkownika po stronie laptopa);
# - aktywacja (switch) zostaje u użytkownika (`update-local`).
# Ryzyko resztkowe: zwykłe konto lokalne widzi usługi na localhost (ollama
# :11434 bez autoryzacji) i może obciążyć CPU/dysk.
#
# RPi (rpi-laptop-remote): `Host laptop` w ssh_config z przypiętym kluczem hosta
# i skrypt `laptop-run`. Działa tylko, gdy laptop jest włączony i w domowym
# LAN-ie. fail2ban laptopa nie ignoruje LAN-u: 5 nieudanych logowań banuje RPi.
{ customTop, ... }:
let
  keys = import "${customTop.secretsDir}/keys.nix";
  user = "claude-remote";
in
{
  flake.modules.nixos.nixos-remote-agent = {
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
  };

  flake.modules.nixos.rpi-laptop-remote =
    { config, pkgs, ... }:
    let
      # laptop-run [CMD...] — uruchamia CMD na laptopie w migawce bieżącego
      # repo (~/work/<repo> konta claude-remote); bez CMD tylko synchronizuje.
      # Migawka = to, co widzi lokalny flake: pliki śledzone z niezacommitowanymi
      # zmianami + nowe pliki dodane do indeksu (nieśledzonych brak). Powstaje
      # jako commit na tymczasowym indeksie — HEAD i indeks repo bez zmian —
      # i jedzie przez `git push` (przyrostowo).
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
          commit=$(git -C "$repo" commit-tree "$tree" -p HEAD -m "laptop-run snapshot")

          ssh laptop "git init -q $qdest"
          git -C "$repo" push -q --force "laptop:$dest" "$commit:refs/heads/laptop-run"

          # Bez -x: ignorowane `result` (dla diff-closures) zostaje.
          remote="cd $qdest && git checkout -q -f --detach laptop-run && git clean -q -fd"
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
