# Tailscale na laptopie i RPi: hostowany serwer koordynacji, wyłącznie
# połączenia wychodzące, więc działa za CGNAT (headscale za tunelem Cloudflare
# nie może, AGENTS.md). Tailnet jest jedyną drogą spoza domowego LAN-u do usług
# RPi: Tailscale Serve wystawia je pod https://<RPi>.<tailnet>:<port>
# (customBot.tailscaleServe, jednostka tailscale-serve), a SSH idzie przez
# tailscale0 (rpi-ssh).
#
# - --netfilter-mode=nodivert na obu hostach: domyślne `on` wstawia na początek
#   INPUT `-i tailscale0 -j ACCEPT`, z którym tailnet omijałby nixos-fw (także
#   SSH tylko z LAN-u). Tailnet dociera więc tylko do portów Serve, które
#   obsługuje netstack w procesie tailscaled, i do portów otwartych w nixos-fw
#   na tailscale0 (SSH RPi, SSH laptopa tylko z telefonu); resztę blokuje
#   nixos-fw.
# - Konta lokalne nie omijają uwierzytelnienia usługi innym wejściem: przy
#   customBot.tailscaleServe.<port>.users z jej portem łączą się lokalnie tylko
#   root (proxy tailscaled) i te konta, a połączenia na własne adresy tailnetu
#   (lokalny listener Serve, idzie przez lo) są odrzucane.
# - DNS: laptop ma systemd-resolved, więc MagicDNS dostaje tylko domenę tailnetu
#   (split DNS na łączu tailscale0), a nazwy *.ts.net rozwiązują się tylko przez
#   niego. RPi: --accept-dns=false, bo bez resolved MagicDNS przejąłby DNS
#   całego hosta.
# - Pierwsze `tailscale up` (bez ControlURL) nie sprawdza ustawień i nadpisuje je
#   domyślnymi, a extraSetFlags działa tylko przy starcie tailscaled, więc
#   tailscale-prefs wymusza je po każdym zalogowaniu (`tailscale wait`).
# - Żadne konto nie dostaje --operator: operator mógłby włączyć Funnel, czyli
#   wystawić usługi do internetu.
# - lockdown: laptop zatrzymuje tailscaled (własne połączenia wychodzące), RPi
#   go zostawia, bo tailnet niesie SSH (zatrzymany odciąłby też sesję, z której
#   włączono lockdown); backendy Serve stoją, więc ich porty dają 502.
#
# Jednorazowo na każdym hoście `sudo tailscale up --netfilter-mode=nodivert`
# (RPi także --accept-dns=false), link logowania otworzyć w przeglądarce, na
# obu hostach to samo konto. W panelu Tailscale: wyłączyć wygasanie klucza RPi,
# włączyć MagicDNS i HTTPS Certificates; Serve włącza w tailnecie link
# z `journalctl -u tailscale-serve` (bez niego porty Serve nie odpowiadają).
# Po usunięciu ostatniego wpisu customBot.tailscaleServe konfiguracja Serve
# zostaje w stanie tailscaled: `sudo tailscale serve reset`.
#
# Sprawdzenie: `tailscale status`, `systemctl status tailscaled tailscale-prefs
# tailscale-serve`, `tailscale serve status`, `sudo iptables -S INPUT` (bez
# skoku do ts-input).
_:
let
  tailscaleWith =
    setFlags:
    { config, lib, ... }:
    let
      tailscale = lib.getExe config.services.tailscale.package;
      serve = config.customBot.tailscaleServe;

      # Firewall przy reloadzie czyści tylko własne łańcuchy, nie OUTPUT, więc
      # przed dodaniem reguła jest usuwana, żeby się nie mnożyła. Bez `-d`:
      # usługa słuchająca na 0.0.0.0 (T3 desktop) jest lokalnie osiągalna
      # także pod adresem LAN, który też idzie przez lo.
      ownerRules = lib.concatLists (
        lib.mapAttrsToList (
          _:
          { port, users }:
          lib.optionals (users != null) (
            map
              (cmd: {
                inherit cmd;
                rule = lib.concatStringsSep " " (
                  [ "OUTPUT -o lo -p tcp --dport ${toString port} -m owner ! --uid-owner root" ]
                  ++ map (user: "-m owner ! --uid-owner ${user}") users
                  ++ [ "-j REJECT" ]
                );
              })
              [
                "iptables"
                "ip6tables"
              ]
          )
        ) serve
      );
      # Lokalny listener Serve (własne adresy tailnetu 100.64.0.0/10 i
      # fd7a:115c:a1e0::/48, idą przez lo) łączy się z usługą jako root, więc
      # omijałby reguły owner.
      outputRules = ownerRules ++ [
        {
          cmd = "iptables";
          rule = "OUTPUT -o lo -d 100.64.0.0/10 -j REJECT";
        }
        {
          cmd = "ip6tables";
          rule = "OUTPUT -o lo -d fd7a:115c:a1e0::/48 -j REJECT";
        }
      ];
      deleteRule = { cmd, rule }: "${cmd} -D ${rule} 2>/dev/null || true";
      appendRule = { cmd, rule }: "${cmd} -A ${rule}";
    in
    {
      services.tailscale.enable = true;

      networking.firewall = lib.mkIf (serve != { }) {
        extraCommands = lib.concatMapStringsSep "\n" (rule: ''
          ${deleteRule rule}
          ${appendRule rule}
        '') outputRules;
        extraStopCommands = lib.concatMapStringsSep "\n" deleteRule outputRules;
      };

      # BindsTo z After: przy lockdown (tailscaled pominięty) też się nie
      # uruchamiają. Typ simple, bo `tailscale wait` czeka do zalogowania,
      # a oneshot zatrzymałby na tym przełączanie konfiguracji.
      systemd.services = {
        tailscale-prefs = {
          description = "Tailscale: ustawienia wymuszane po zalogowaniu";
          wantedBy = [ "tailscaled.service" ];
          bindsTo = [ "tailscaled.service" ];
          after = [ "tailscaled.service" ];
          script = ''
            ${tailscale} wait
            ${tailscale} set ${lib.escapeShellArgs setFlags}
          '';
          serviceConfig = {
            Restart = "on-failure";
            RestartSec = "1min";
          };
        };

        # reset przed dodaniem: port usunięty z mapy nie zostaje w stanie
        # tailscaled. RemainAfterExit: jednostka zostaje aktywna, więc
        # switch-to-configuration restartuje ją po zmianie mapy (nieaktywnej
        # by nie ruszył). Gdy Serve nie jest włączony w tailnecie,
        # `tailscale serve` czeka i wypisuje link do włączenia; po włączeniu
        # kończy sam. multi-user.target: switch-to-configuration uruchamia
        # nowe jednostki tylko z aktywnych targetów, a tailscaled się przy nim
        # nie restartuje.
        tailscale-serve = lib.mkIf (serve != { }) {
          description = "Tailscale Serve: porty HTTPS tailnetu (customBot.tailscaleServe)";
          wantedBy = [
            "multi-user.target"
            "tailscaled.service"
          ];
          bindsTo = [ "tailscaled.service" ];
          after = [ "tailscaled.service" ];
          script = ''
            ${tailscale} wait
            ${tailscale} serve reset
          ''
          + lib.concatLines (
            lib.mapAttrsToList (
              httpsPort:
              { port, ... }:
              "${tailscale} serve --bg --yes --https=${lib.escapeShellArg httpsPort} http://127.0.0.1:${toString port}"
            ) serve
          );
          serviceConfig = {
            RemainAfterExit = true;
            Restart = "on-failure";
            RestartSec = "1min";
          };
        };
      };
    };
in
{
  flake.modules.nixos.nixos-tailscale = {
    imports = [ (tailscaleWith [ "--netfilter-mode=nodivert" ]) ];
    customBot.lockdownServices = [ "tailscaled" ];
  };

  flake.modules.nixos.rpi-tailscale = tailscaleWith [
    "--accept-dns=false"
    "--netfilter-mode=nodivert"
  ];
}
