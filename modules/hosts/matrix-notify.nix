# Powiadomienia agentów AI przez Matrix: bot @notify na serwerze rpi-matrix
# pisze do pokoju #notify, do którego należy właściciel
# (@<customTop.users.laptop>), a aplikacja Matrix na telefonie i laptopie
# pokazuje je jak wiadomości z rozmowy. Polecenie `matrix-notify` na laptopie
# (konto główne, przez https://<RPi>.<tailnet>:8448) i na RPi (konto t3code,
# przez 127.0.0.1), skill matrix-notify oraz hooki Claude Code, które przez
# nie zgłaszają prośbę o zgodę (Notification) i koniec odpowiedzi (Stop,
# m.notice: bez dźwięku).
#
# Granica zaufania:
# - Token bota (matrix-notify.age) to nagłówek dla `curl -H @plik`, nigdy na
#   linii poleceń; na każdym hoście czyta go tylko jedno konto. Bot nie jest
#   administratorem i nie ma tokenu rejestracji, więc z jego tokenem można
#   pisać i czytać tylko w pokojach bota.
# - Pokój jest bez E2EE (curl nie szyfruje): treść powiadomień z laptopa
#   zostaje w bazie serwera na RPi, więc czyta ją root RPi; dlatego hook Stop
#   wysyła tylko początek ostatniej odpowiedzi.
#
# Jednorazowo, po koncie właściciela (nagłówek rpi-matrix), na laptopie
# w modules/_secrets/ (fish):
#   set -l header (ssh root@raspberry-pi-4 matrix-notify-setup)
#   and printf '%s\n' $header | agenix -e matrix-notify.age
# (stdin bez terminala szyfruje bez klucza prywatnego), commit, przebudowa
# obu hostów, w aplikacji przyjąć zaproszenie do pokoju „Powiadomienia
# agentów AI”. Do tego czasu ostrzeżenie ewaluacji, a `matrix-notify` kończy
# się błędem. Nowy token: dezaktywacja bota i aliasu w #admins, potem znowu
# setup.
#
# Sprawdzenie: `matrix-notify -t test "działa"` na laptopie i jako t3code na
# RPi (`sudo -u t3code matrix-notify …`); `cat
# /etc/claude-code/managed-settings.d/matrix-notify.json`.
_:
let
  serverHost = "raspberry-pi-4";
  # Port Serve serwera (rpi-matrix); laptop nie czyta konfiguracji RPi, więc
  # zgodność sprawdza asercja w rpi-matrix-notify.
  servePort = 8448;
  bot = "notify";
  roomAlias = "notify";

  client =
    { homeserver, owner }:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      serverName = "${serverHost}.${config.customTop.tailnet.domain}";
      secretFile = config.customTop.secretsDir + "/matrix-notify.age";
      hasSecret = builtins.pathExists secretFile;
      tokenFile = "${config.age.secretsDir}/matrix-notify";

      matrixNotify = pkgs.writeShellApplication {
        name = "matrix-notify";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
        ];
        runtimeEnv = {
          HOMESERVER = homeserver;
          ROOM_ALIAS = "#${roomAlias}:${serverName}";
          TOKEN_FILE = tokenFile;
        };
        text = builtins.readFile ./_matrix-notify/matrix-notify.sh;
      };

      # Hook nigdy nie przerywa pracy agenta: bez tokenu (inne konto) albo
      # bez łączności po prostu nic nie wysyła.
      claudeHook = pkgs.writeShellApplication {
        name = "matrix-notify-claude-hook";
        runtimeInputs = [
          pkgs.jq
          matrixNotify
        ];
        text = ''
          host=${lib.escapeShellArg config.networking.hostName}
          input=$(cat)
          project=$(jq -r '.cwd // "" | split("/") | last // ""' <<<"$input")
          case $(jq -r .hook_event_name <<<"$input") in
            Notification)
              message=$(jq -r .message <<<"$input")
              quiet=()
              ;;
            Stop)
              message=$(jq -r '.last_assistant_message // "" | .[:300]' <<<"$input")
              quiet=(-q)
              ;;
            *) exit 0 ;;
          esac
          matrix-notify "''${quiet[@]}" -t "Claude $host: $project" \
            "''${message:-Gotowe}" >/dev/null 2>&1 || true
        '';
      };

      hook = {
        type = "command";
        command = lib.getExe claudeHook;
        timeout = 15;
      };
    in
    {
      warnings = lib.optionals (!hasSecret) [
        "matrix-notify: brak modules/_secrets/matrix-notify.age w gicie — agenci nie wyślą powiadomień (nagłówek modules/hosts/matrix-notify.nix)."
      ];

      age.secrets.matrix-notify = lib.mkIf hasSecret {
        file = secretFile;
        path = tokenFile;
        inherit owner;
      };

      environment = {
        systemPackages = [ matrixNotify ];
        # idle_prompt pomija, bo Stop zgłasza już koniec odpowiedzi;
        # auth_success nie jest dla telefonu.
        etc."claude-code/managed-settings.d/matrix-notify.json".text = builtins.toJSON {
          hooks = {
            Notification = [
              {
                matcher = "permission_prompt|elicitation_dialog";
                hooks = [ hook ];
              }
            ];
            Stop = [ { hooks = [ hook ]; } ];
          };
        };
      };
    };
in
{
  flake.modules.nixos.nixos-matrix-notify =
    { config, ... }:
    {
      imports = [
        (client {
          homeserver = "https://${serverHost}.${config.customTop.tailnet.domain}:${toString servePort}";
          owner = config.customBot.defaultUser;
        })
      ];
    };

  flake.modules.nixos.rpi-matrix-notify =
    { config, pkgs, ... }:
    let
      continuwuity = config.services.matrix-continuwuity.settings.global;
      homeserver = "http://${builtins.head continuwuity.address}:${toString (builtins.head continuwuity.port)}";
      ownerName = config.customTop.users.laptop;

      setup = pkgs.writeShellApplication {
        name = "matrix-notify-setup";
        runtimeInputs = with pkgs; [
          coreutils
          curl
          jq
        ];
        runtimeEnv = {
          HOMESERVER = homeserver;
          OWNER = ownerName;
          OWNER_ID = "@${ownerName}:${continuwuity.server_name}";
          BOT = bot;
          BOT_ID = "@${bot}:${continuwuity.server_name}";
          ROOM_ALIAS_NAME = roomAlias;
          REGISTRATION_TOKEN_FILE = config.age.secrets.continuwuity-registration-token.path;
        };
        text = builtins.readFile ./_matrix-notify/setup.sh;
      };
    in
    {
      imports = [
        (client {
          inherit homeserver;
          owner = config.systemd.services.t3code.serviceConfig.User;
        })
      ];

      assertions = [
        {
          assertion =
            continuwuity.server_name == "${serverHost}.${config.customTop.tailnet.domain}"
            &&
              config.customBot.tailscaleServe.${toString servePort}.port or null
              == builtins.head continuwuity.port;
          message = "matrix-notify: laptop łączy się z https://${serverHost}.<tailnet>:${toString servePort}, a rpi-matrix ma server_name ${continuwuity.server_name} i inny wpis Serve; popraw serverHost lub servePort w modules/hosts/matrix-notify.nix.";
        }
      ];

      # Tylko root przeczyta token rejestracji, więc tylko root założy bota.
      environment.systemPackages = [ setup ];
    };
}
