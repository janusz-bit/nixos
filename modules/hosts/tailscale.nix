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
#   na tailscale0 (SSH RPi); resztę blokuje nixos-fw.
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
    in
    {
      services.tailscale.enable = true;

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
              port: target:
              "${tailscale} serve --bg --yes --https=${lib.escapeShellArg port} ${lib.escapeShellArg target}"
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
