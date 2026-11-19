# Powiadomienia push na telefon: serwer ntfy na raspberry-pi-4 w tailnecie
# (Tailscale Serve na https://<RPi>.<tailnet>:2586), polecenie
# `notify-phone` na laptopie i RPi oraz hooki Claude Code, które przez nie
# zgłaszają prośbę o zgodę (Notification) i koniec odpowiedzi (Stop). Nic nie
# wychodzi do internetu: telefon z aplikacją ntfy (F-Droid, „instant
# delivery”) trzyma połączenie z serwerem przez Tailscale.
#
# Granica zaufania:
# - auth-default-access = deny-all; użytkownicy i token są deklaratywne
#   (NTFY_AUTH_USERS, NTFY_AUTH_TOKENS z ntfy-server.age, czytane przez
#   systemd jako EnvironmentFile roota), ACL w auth-access: `phone` tylko
#   czyta, `claude` (token z ntfy-token.age) tylko publikuje. Konto t3code na
#   mniej zaufanym RPi wysyła więc powiadomienia, ale nie czyta tych
#   z laptopa.
# - Z backendem 127.0.0.1:2586 łączy się lokalnie tylko root (proxy
#   tailscaled) i t3code (customBot.tailscaleServe.users). Token idzie do curl
#   z pliku (`-H @plik`), nigdy przez linię poleceń.
# - Ryzyko resztkowe: treść powiadomień z laptopa leży w cache ntfy na RPi
#   (domyślnie 12 h), więc root RPi może ją przeczytać; dlatego hook Stop
#   wysyła tylko początek ostatniej odpowiedzi.
#
# Sekrety (formaty w _secrets/secrets.nix) tworzy się na laptopie w
# modules/_secrets/: token `ntfy token generate`, hashe bcrypt `ntfy user
# hash` (hasło telefonu; dla `claude` losowe, bo loguje się tylko tokenem),
# zapis `… | agenix -e <plik>.age` (stdin bez terminala szyfruje bez klucza
# prywatnego). Zmiana tokenu: oba pliki naraz.
# Telefon: w aplikacji ntfy dodać użytkownika `phone` dla
# https://<RPi>.<tailnet>:2586, zasubskrybować temat `claude` z „use another
# server” i wyłączyć dla aplikacji optymalizację baterii.
#
# Sprawdzenie: na RPi `systemctl status ntfy-sh tailscale-serve`, `tailscale
# serve status`; `notify-phone -t test "działa"` na laptopie i jako t3code
# (`sudo -u t3code notify-phone …`); `curl -s
# https://<RPi>.<tailnet>:2586/claude/json?poll=1` bez logowania daje 403.
_:
let
  serverHost = "raspberry-pi-4";
  port = 2586;
  topic = "claude";

  client =
    { baseUrl, owner }:
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      notifyPhone = pkgs.writeShellApplication {
        name = "notify-phone";
        runtimeInputs = with pkgs; [
          curl
          jq
        ];
        # Publikacja w JSON, bo nagłówek Title nie przenosi UTF-8.
        text = ''
          usage() {
            echo "usage: notify-phone [-t title] [-p priority 1-5] message" >&2
            exit 2
          }
          title=""
          priority=3
          while getopts t:p: opt; do
            case $opt in
              t) title=$OPTARG ;;
              p) priority=$OPTARG ;;
              *) usage ;;
            esac
          done
          shift $((OPTIND - 1))
          [ $# -gt 0 ] || usage
          [[ $priority =~ ^[1-5]$ ]] || usage

          # Usługa może dostać token jako poświadczenie systemd (LoadCredential
          # ntfy-token, np. rpi-picoclaw) zamiast pliku tego konta.
          token=${lib.escapeShellArg config.age.secrets.ntfy-token.path}
          if [ -r "''${CREDENTIALS_DIRECTORY:-}/ntfy-token" ]; then
            token=$CREDENTIALS_DIRECTORY/ntfy-token
          fi

          jq -n \
            --arg topic ${lib.escapeShellArg topic} \
            --arg title "$title" \
            --arg message "$*" \
            --argjson priority "$priority" \
            '{$topic, $message, $priority} + (if $title == "" then {} else {$title} end)' |
            curl -fsS --max-time 10 -o /dev/null \
              -H @"$token" \
              --data-binary @- ${lib.escapeShellArg baseUrl}
        '';
      };

      # Hook nigdy nie przerywa pracy agenta: bez tokenu (inne konto) albo
      # bez łączności po prostu nic nie wysyła.
      claudeHook = pkgs.writeShellApplication {
        name = "notify-phone-claude-hook";
        runtimeInputs = [
          pkgs.jq
          notifyPhone
        ];
        text = ''
          host=${lib.escapeShellArg config.networking.hostName}
          input=$(cat)
          project=$(jq -r '.cwd // "" | split("/") | last // ""' <<<"$input")
          case $(jq -r .hook_event_name <<<"$input") in
            Notification)
              message=$(jq -r .message <<<"$input")
              priority=3
              ;;
            Stop)
              message=$(jq -r '.last_assistant_message // "" | .[:300]' <<<"$input")
              priority=2
              ;;
            *) exit 0 ;;
          esac
          notify-phone -t "Claude $host: $project" -p "$priority" \
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
      age.secrets.ntfy-token = {
        file = config.customTop.secretsDir + "/ntfy-token.age";
        inherit owner;
      };

      environment = {
        systemPackages = [ notifyPhone ];
        # idle_prompt pomija, bo Stop zgłasza już koniec odpowiedzi;
        # auth_success nie jest dla telefonu.
        etc."claude-code/managed-settings.d/notify-phone.json".text = builtins.toJSON {
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
  flake.modules.nixos.nixos-ntfy =
    { config, ... }:
    {
      imports = [
        (client {
          baseUrl = "https://${serverHost}.${config.customTop.tailnet.domain}:${toString port}";
          owner = config.customBot.defaultUser;
        })
      ];
    };

  flake.modules.nixos.rpi-ntfy =
    { config, ... }:
    let
      t3User = config.systemd.services.t3code.serviceConfig.User;
    in
    {
      imports = [
        (client {
          baseUrl = "http://127.0.0.1:${toString port}";
          owner = t3User;
        })
      ];

      age.secrets.ntfy-server.file = config.customTop.secretsDir + "/ntfy-server.age";

      services.ntfy-sh = {
        enable = true;
        settings = {
          base-url = "https://${config.networking.hostName}.${config.customTop.tailnet.domain}:${toString port}";
          listen-http = "127.0.0.1:${toString port}";
          auth-default-access = "deny-all";
          auth-access = [
            "phone:${topic}:read-only"
            "claude:${topic}:write-only"
          ];
          # Telefon korzysta z aplikacji, a aplikacja WWW byłaby tylko
          # kolejnym formularzem logowania w tailnecie.
          web-root = "disable";
        };
        environmentFile = config.age.secrets.ntfy-server.path;
      };

      customBot = {
        tailscaleServe.${toString port} = {
          inherit port;
          users = [ t3User ];
        };
        lockdownServices = [ "ntfy-sh" ];
      };
    };
}
