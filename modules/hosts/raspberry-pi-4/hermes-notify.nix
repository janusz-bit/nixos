# claude-notify: powiadomienia Claude Code do DM na Matrixie przez Hermesa.
#
# Po co: Claude Code daje znać (skończone dłuższe zadanie, pytanie, które go
# blokuje), gdy nikt nie patrzy w terminal. Bez LLM: `hermes send` na RPi
# wysyła gotowy tekst adapterem Matrixa Hermesa (konto bota, E2EE) do DM
# z MATRIX_HOME_ROOM (matrix.nix).
#
# Droga wiadomości:
# - laptop (nixos-hermes-notify): claude-notify → ssh przez tunel cloudflared
#   (ssh.<domena>) → sshd RPi, które widzi połączenie z localhost → konto
#   hermes z wymuszonym poleceniem hermes-notify-receive → hermes send;
# - RPi (rpi-hermes-notify) jako nixos: to samo przez ssh na localhost;
# - RPi jako hermes (brama i jej procesy, np. `claude -p`): odbiornik wprost.
#
# Granica zaufania: klucz z hermes-notify-key.age (laptop: dinosaur 0400; RPi:
# hermes:hermes 0440, nixos czyta przez grupę) loguje tylko na konto hermes,
# tylko z 127.0.0.1/::1 (tunel i localhost, nie z LAN-u), z `restrict` (bez pty,
# przekierowań i agenta) i z wymuszonym poleceniem. Odbiornik ignoruje
# SSH_ORIGINAL_COMMAND i argumenty: bierze wyłącznie tekst ze stdin (do 3500
# bajtów, najwyżej 30 wiadomości na godzinę) i wysyła go do jednego, stałego
# DM. Wyciek klucza pozwala więc najwyżej zaspamować ten DM w granicach limitu.
# Samo konto hermes nic nie zyskuje: `hermes send` mogło wywołać i bez tego.
# Klient przypina klucz hosta RPi (keys.sshHostKeys) i pomija ssh_config
# (-F /dev/null), bo base-ssh ma `Host ssh.*` → User root.
#
# Claude Code: skill hermes-notify (kiedy i jak pisać) oraz ustawienia
# zarządzane z hookiem Notification i regułą allow (claudeCodeSettings niżej).
# claude-notify nie trafia do skillPackages (modules/skills/default.nix): cel
# ssh, ścieżka klucza i odbiornik zależą od hosta, więc pakiet powstaje tutaj.
#
# Test po wdrożeniu (RPi dopiero po merge do master i `update`, laptop po
# `update-local`): `echo test | claude-notify` na obu hostach, na RPi także
# `sudo -u hermes claude-notify test` (ścieżka bez ssh). Odbiornik: pusty stdin
# albo 31. wiadomość w ciągu godziny → kod 1 i komunikat na stderr. Hook: w
# sesji Claude Code w tmux polecenie, które wymaga zgody (prompt uprawnień).
{ customTop, lib, ... }:
let
  keys = import "${customTop.secretsDir}/keys.nix";

  # Dopóki pliku nie ma w gicie (flake widzi tylko śledzone pliki), funkcja jest
  # wyłączona, a ewaluacja tylko ostrzega.
  secretFile = customTop.secretsDir + "/hermes-notify-key.age";
  hasSecret = builtins.pathExists secretFile;

  rpi = "raspberry-pi-4";
  hermesUser = "hermes";

  # claude-notify [TEKST...] — TEKST (bez argumentów: stdin) do DM.
  # claude-notify --hook — JSON hooka Notification Claude Code na stdin.
  mkClaudeNotify =
    {
      pkgs,
      ssh,
      tmux,
      key,
      target,
      sshOptions ? [ ],
      receiver ? null,
    }:
    let
      # HostKeyAlias: ten sam wpis niezależnie od celu (tunel albo localhost).
      knownHosts = pkgs.writeText "hermes-notify-known-hosts" "${rpi} ${keys.sshHostKeys.${rpi}}\n";
      # Limit z zapasem: wysyłka przez `hermes send` na RPi trwa 22–31 s
      # (zmierzone 2026-10-11), a przy 20 s wiadomość dochodziła mimo kodu 124.
      # -T: odbiornik nie dostaje pty (`restrict`), więc bez ostrzeżenia ssh.
      sshCommand = [
        "timeout"
        "60"
        "ssh"
        "-T"
        "-F"
        "/dev/null"
        "-i"
        key
        "-o"
        "IdentitiesOnly=yes"
        "-o"
        "BatchMode=yes"
        "-o"
        "ConnectTimeout=10"
        "-o"
        "StrictHostKeyChecking=yes"
        "-o"
        "HostKeyAlias=${rpi}"
        "-o"
        "UserKnownHostsFile=${knownHosts}"
      ]
      ++ sshOptions
      ++ [ "${hermesUser}@${target}" ];
    in
    pkgs.writeShellApplication {
      name = "claude-notify";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.gawk
        pkgs.jq
        ssh
        tmux
      ];
      text = ''
        # U+1F916 (robot) i U+23F8 U+FE0F (pauza) jako bajty UTF-8: nie zależą
        # od locale procesu (hook, usługa), a źródło zostaje bez emoji.
        robot=$'\xf0\x9f\xa4\x96'
        pause=$'\xe2\x8f\xb8\xef\xb8\x8f'
        key=${lib.escapeShellArg key}
        receiver=${lib.escapeShellArg (lib.optionalString (receiver != null) (lib.getExe receiver))}
        user=$(id -un)

        hook=false
        if [[ ''${1-} == --hook ]]; then
          hook=true
          # Hook nie może przeszkadzać sesji: każdy błąd (np. konto bez dostępu
          # do klucza, jak claude-remote) kończy się po cichu kodem 0.
          exec 2>/dev/null
          trap 'exit 0' EXIT
        fi

        fail() {
          printf 'claude-notify: %s\n' "$1" >&2
          exit 1
        }

        if $hook; then
          input=$(cat)
          cwd=$(jq -r '.cwd // empty' <<<"$input")
          text="$pause Claude czeka ($(jq -r '.notification_type // "?"' <<<"$input")): $(jq -r '.message // ""' <<<"$input")"
          # Kontekst z ekranu: ostatnie niepuste linie panelu tmux z sesją.
          if [[ -n ''${TMUX_PANE-} ]] && pane=$(tmux capture-pane -p -J -t "$TMUX_PANE" | awk NF | tail -n 15); then
            text+=$'\n\n'$pane
          fi
        else
          cwd=$PWD
          if (($#)); then
            text=$*
          else
            text=$(cat)
          fi
          [[ -n ''${text//[[:space:]]/} ]] || fail "pusty tekst (podaj go jako argument albo na stdin)"
        fi

        header="$robot $HOSTNAME · $user"
        if [[ -n ''${TMUX-} ]] && session=$(tmux display-message -p '#S' 2>/dev/null); then
          header+=" · $session"
        fi
        header+=" · $(basename "''${cwd:-$PWD}")"

        # Konto usługi (brama i jej procesy) woła odbiornik wprost; klucz
        # hermes:hermes 0440 jest dla innych członków grupy hermes.
        if [[ -n $receiver && $user == ${hermesUser} ]]; then
          send=("$receiver")
        else
          [[ -r $key ]] || fail "brak dostępu do klucza $key (konto $user)"
          send=(${lib.escapeShellArgs sshCommand})
        fi
        "''${send[@]}" <<<"$header"$'\n'"$text" || fail "wysyłka nie powiodła się (kod $?)"
      '';
    };

  # Ustawienia zarządzane Claude Code (każdy użytkownik i projekt hosta).
  # Hook: prośby o zgodę i pytania MCP; koniec pracy zgłasza skill
  # hermes-notify (modules/skills), dlatego bez Stop i idle_prompt.
  # `Bash(claude-notify *)` to w 2.1.285 `^claude-notify( .*)?$`, więc obejmuje
  # też samo `claude-notify` z tekstem na stdin.
  # Obejmuje też `claude -p` pluginu claude-subscription-directsdk Hermesa
  # (--setting-sources "" nie wyłącza ustawień zarządzanych), ale go nie
  # zmienia: plugin daje --tools "" (bez Bash), --disable-slash-commands (bez
  # skilli) i --permission-mode dontAsk (bez próśb o zgodę), a jego serwer MCP
  # nie prosi o elicitation.
  claudeCodeSettings = pkgs: claudeNotify: {
    "claude-code/managed-settings.d/50-hermes-notify.json".source =
      (pkgs.formats.json { }).generate "50-hermes-notify.json"
        {
          permissions.allow = [ "Bash(claude-notify *)" ];
          hooks.Notification = [
            {
              matcher = "permission_prompt|elicitation_dialog";
              hooks = [
                {
                  type = "command";
                  command = "${lib.escapeShellArg (lib.getExe claudeNotify)} --hook";
                  async = true;
                }
              ];
            }
          ];
        };
  };
in
{
  flake.modules.nixos.rpi-hermes-notify =
    { config, pkgs, ... }:
    let
      cfg = config.services.hermes-agent;
      # Bez hermes-matrix.age matrix.nix nie ustawia pokoju (i tylko ostrzega).
      room = cfg.environment.MATRIX_HOME_ROOM or null;
      enable = hasSecret && room != null;

      receiver = pkgs.writeShellApplication {
        name = "hermes-notify-receive";
        runtimeInputs = with pkgs; [
          coreutils
          gawk
          gnused
          util-linux
        ];
        text = ''
          # Argumenty i SSH_ORIGINAL_COMMAND są ignorowane: jedyne wejście to
          # tekst na stdin, cel jest stały.
          limit=30
          state=${lib.escapeShellArg "${config.users.users.${cfg.user}.home}/.cache/hermes-notify"}

          # Najwyżej 3500 bajtów; gdy cięcie wypadło w środku znaku UTF-8, sed
          # (bajtowo, locale C) usuwa z końca jego niepełną sekwencję.
          text=$(head -c 3500 | LC_ALL=C sed -z -E $'s/([\xc0-\xdf]|[\xe0-\xef][\x80-\xbf]?|[\xf0-\xf7][\x80-\xbf]{0,2})$//')
          if [[ -z ''${text//[[:space:]]/} ]]; then
            echo "hermes-notify-receive: pusty tekst" >&2
            exit 1
          fi

          # Znaczniki czasu wysyłek z ostatniej godziny; flock, bo naraz mogą
          # przyjść wiadomości z tunelu, z localhost i od samego Hermesa.
          mkdir -p "$state"
          {
            flock 9
            now=$(date +%s)
            touch "$state/sent"
            mapfile -t recent < <(awk -v since="$((now - 3600))" '$1 > since' "$state/sent")
            if ((''${#recent[@]} >= limit)); then
              echo "hermes-notify-receive: wyczerpany limit $limit wiadomości na godzinę" >&2
              exit 1
            fi
            printf '%s\n' "''${recent[@]}" "$now" >"$state/sent"
          } 9>"$state/lock"

          # stderr: mautrix wypisuje przy zamykaniu nieszkodliwe tracebacki.
          # Kod wyjścia hermes send przechodzi dalej (exec).
          exec ${lib.getExe cfg.cliWrapper} send --to ${lib.escapeShellArg "matrix:${room}"} -q -f - <<<"$text" 2>/dev/null
        '';
      };

      claudeNotify = mkClaudeNotify {
        inherit pkgs receiver;
        ssh = config.programs.ssh.package;
        tmux = config.programs.tmux.package;
        key = config.age.secrets.hermes-notify-key.path;
        target = "localhost";
      };
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!enable) [
          "hermes-notify: brak modules/_secrets/hermes-notify-key.age w gicie albo MATRIX_HOME_ROOM (hermes-matrix.age, matrix.nix) — claude-notify wyłączone."
        ];
      }
      (lib.mkIf enable {
        # Klucz klienta dla nixos (grupa hermes). ssh nie odrzuca go jako
        # „too open”: tryb sprawdza tylko u właściciela pliku, a hermes
        # (właściciel) nie używa ssh, tylko woła odbiornik wprost.
        age.secrets.hermes-notify-key = {
          file = secretFile;
          owner = cfg.user;
          inherit (cfg) group;
          mode = "0440";
        };

        # Przez /etc/ssh/authorized_keys.d, nie ~/.ssh: katalog domowy hermes
        # (2770) jest zapisywalny dla grupy, więc StrictModes odrzuciłby
        # ~/.ssh/authorized_keys.
        users.users.${cfg.user}.openssh.authorizedKeys.keys = [
          ''from="127.0.0.1,::1",restrict,command="${lib.getExe receiver}" ${keys.users.hermes-notify}''
        ];

        environment = {
          systemPackages = [ claudeNotify ];
          etc = claudeCodeSettings pkgs claudeNotify;
        };
      })
    ];

  flake.modules.nixos.nixos-hermes-notify =
    { config, pkgs, ... }:
    let
      claudeNotify = mkClaudeNotify {
        inherit pkgs;
        ssh = config.programs.ssh.package;
        tmux = config.programs.tmux.package;
        key = config.age.secrets.hermes-notify-key.path;
        target = "ssh.${customTop.site.full}";
        sshOptions = [
          "-o"
          "ProxyCommand=${lib.getExe pkgs.cloudflared} access ssh --hostname %h"
        ];
      };
    in
    lib.mkMerge [
      {
        warnings = lib.optionals (!hasSecret) [
          "hermes-notify: brak modules/_secrets/hermes-notify-key.age w gicie — claude-notify wyłączone."
        ];
      }
      (lib.mkIf hasSecret {
        age.secrets.hermes-notify-key = {
          file = secretFile;
          owner = config.customBot.defaultUser;
          mode = "0400";
        };

        environment = {
          systemPackages = [ claudeNotify ];
          etc = claudeCodeSettings pkgs claudeNotify;
        };
      })
    ];
}
