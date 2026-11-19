# Asystent picoclaw (llm-agents) na RPi: `picoclaw gateway` na koncie
# systemowym picoclaw, rozmowa przez Matrix (bot @picoclaw na serwerze
# rpi-matrix, odpowiada tylko właścicielowi @<customTop.users.laptop>),
# modelem jest Claude Code (provider claude-cli: każda tura to `claude -p`
# z subskrypcji Claude), powiadomienia na telefon przez `notify-phone` (ntfy,
# rpi-ntfy) i własne zadania cykliczne (narzędzie cron picoclaw).
#
# - Konfiguracja: config.json ze schematem 3 z Nixa (aktualny schemat nie jest
#   migrowany ani zapisywany z powrotem), przy starcie uzupełniony w katalogu
#   runtime o sesję bota i klucz bazy E2EE (_picoclaw/start.sh). Pamięć,
#   sesje, plan zadań i pliki osobowości (AGENT.md, SOUL.md, USER.md) to stan
#   agenta w /var/lib/picoclaw/workspace.
# - Claude Code działa z --dangerously-skip-permissions w katalogu roboczym
#   agenta, czyli ze swoimi narzędziami (Bash, Edit) bez pytania, w granicach
#   konta picoclaw. Hooki telefonu Claude Code (rpi-ntfy) są w tej usłudze
#   wyłączone: każda tura modelu to osobne `claude -p`, więc Stop wysyłałby
#   powiadomienie po każdym kroku; o powiadomieniach decyduje picoclaw.
# - Rozliczenie: Anthropic uznaje te wywołania za aplikację zewnętrzną i liczy
#   je z płatnego extra usage konta, nie z limitów planu (bez niego API
#   odpowiada 400 „Third-party apps now draw from your extra usage”).
# - Konto bota zakłada picoclaw-matrix-register (_picoclaw/register.sh)
#   tokenem rejestracji, którego sam gateway nie dostaje (poświadczenie tylko
#   tej jednostki), więc agent nie założy kolejnych kont. Czeka (ponawia co
#   5 min), aż istnieje konto właściciela, bo pierwsze konto zostaje
#   administratorem serwera. Gateway uruchamia picoclaw.path, gdy pojawi się
#   sesja bota.
# - Skille: ai.skills z agentem picoclaw (ai-harness, /etc/picoclaw/skills).
#   Rejestry skilli (ClawHub, GitHub) wyłączone: kod pobierany w trakcie
#   działania nie jest przypięty.
# - Granica zaufania: agent ma powłokę konta picoclaw (exec, cron) i pisze do
#   niego tylko właściciel (allow_from). Konto nie ma grup, sudo ani sekretów
#   poza tokenem ntfy (tylko publikacja, LoadCredential), własną sesją
#   Matrix i logowaniem Claude Code; do portu ntfy dopuszcza je
#   customBot.tailscaleServe.users.
#
# Jednorazowo: logowanie Claude Code na koncie usługi (`sudo -u picoclaw -H
# claude auth login`), konto właściciela na serwerze Matrix (nagłówek
# rpi-matrix), potem w aplikacji rozmowa z @picoclaw:<RPi>.<tailnet> (bot sam dołącza
# po zaproszeniu).
#
# Sprawdzenie: `systemctl status picoclaw-matrix-register picoclaw.path
# picoclaw`, `journalctl -u picoclaw -b`, `curl -s
# http://127.0.0.1:18790/health`; w rozmowie poprosić o powiadomienie na
# telefon.
{ inputs, ... }:
{
  flake.modules.nixos.rpi-picoclaw =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = "picoclaw";
      home = "/var/lib/${user}";
      session = "${home}/matrix-session.json";

      picoclaw = inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.picoclaw;

      matrix = config.services.matrix-continuwuity.settings.global;
      homeserver = "http://${lib.head matrix.address}:${toString (lib.head matrix.port)}";

      workspace = "${home}/workspace";

      configTemplate = (pkgs.formats.json { }).generate "picoclaw-config.json" {
        version = 3;
        agents.defaults = {
          inherit workspace;
          model_name = "claude-code";
        };
        # Model `claude-code`: bez --model, czyli domyślny model konta Claude.
        model_list = [
          {
            model_name = "claude-code";
            provider = "claude-cli";
            model = "claude-code";
            inherit workspace;
            enabled = true;
          }
        ];
        channel_list.matrix = {
          enabled = true;
          type = "matrix";
          # Forma kanoniczna `platforma:id`: picoclaw dzieli wpis na pierwszym
          # dwukropku, więc goły identyfikator Matrix (@user:serwer) nie pasuje
          # do nikogo.
          allow_from = [ "matrix:@${config.customTop.users.laptop}:${matrix.server_name}" ];
          settings = {
            inherit homeserver;
            join_on_invite = true;
          };
        };
        gateway.host = "127.0.0.1";
        tools.skills.enabled = false;
      };

      register = pkgs.writeShellApplication {
        name = "picoclaw-matrix-register";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
        ];
        runtimeEnv = {
          HOMESERVER = homeserver;
          OWNER = config.customTop.users.laptop;
          BOT = user;
          SESSION = session;
        };
        text = builtins.readFile ./_picoclaw/register.sh;
      };

      start = pkgs.writeShellApplication {
        name = "picoclaw-start";
        runtimeInputs = [
          pkgs.coreutils
          pkgs.jq
          picoclaw
        ];
        runtimeEnv = {
          CONFIG_TEMPLATE = configTemplate;
          SESSION = session;
        };
        text = builtins.readFile ./_picoclaw/start.sh;
      };

      # Klucz wpisu Serve ntfy to jego port HTTP (rpi-ntfy).
      ntfyPort = lib.last (lib.splitString ":" config.services.ntfy-sh.settings.listen-http);

      sandbox = {
        User = user;
        Group = user;
        StateDirectory = user;
        StateDirectoryMode = "0700";
        UMask = "0077";
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
      };
    in
    {
      users = {
        users.${user} = {
          isSystemUser = true;
          group = user;
          inherit home;
        };
        groups.${user} = { };
      };

      systemd.services = {
        picoclaw-matrix-register = {
          description = "picoclaw: konto bota na serwerze Matrix";
          wantedBy = [ "multi-user.target" ];
          requires = [ "continuwuity.service" ];
          after = [ "continuwuity.service" ];
          serviceConfig = sandbox // {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = lib.getExe register;
            LoadCredential = [
              "registration-token:${config.age.secrets.continuwuity-registration-token.path}"
            ];
            Restart = "on-failure";
            RestartSec = "5min";
          };
        };

        picoclaw = {
          description = "picoclaw gateway (Matrix)";
          after = [
            "picoclaw-matrix-register.service"
            "continuwuity.service"
          ];
          # claude dla providera claude-cli; reszta systemu (w tym notify-phone)
          # dla narzędzia exec agenta.
          path = [
            pkgs.claude-code
            "/run/current-system/sw"
          ];
          environment = {
            HOME = home;
            PICOCLAW_HOME = home;
            PICOCLAW_BUILTIN_SKILLS = "/etc/picoclaw/skills";
            # Bez TZ picoclaw podaje modelowi datę bez nazwy strefy.
            TZ = config.time.timeZone;
            NOTIFY_PHONE_CLAUDE_HOOKS = "off";
          };
          serviceConfig = sandbox // {
            ExecStart = lib.getExe start;
            WorkingDirectory = home;
            RuntimeDirectory = user;
            RuntimeDirectoryMode = "0700";
            # notify-phone czyta token z $CREDENTIALS_DIRECTORY/ntfy-token.
            LoadCredential = [ "ntfy-token:${config.age.secrets.ntfy-token.path}" ];
            Restart = "on-failure";
            RestartSec = "30s";
          };
        };
      };

      systemd.paths.picoclaw = {
        wantedBy = [ "multi-user.target" ];
        pathConfig.PathExists = session;
      };

      customBot = {
        tailscaleServe.${ntfyPort}.users = [ user ];
        # Agent łączy się z internetem sam (Claude Code, narzędzia web).
        lockdownServices = [ user ];
      };
    };
}
