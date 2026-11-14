# T3 Code z raspberry-pi-4 wysyła sesje na laptopa: serwer T3 na RPi (konto
# t3code, rpi-t3code) łączy się jako środowisko z T3 desktop laptopa, które
# Tailscale Serve wystawia w tailnecie pod https://nixos.<tailnet> (443 ->
# 127.0.0.1:3773). Nazwa laptopa na RPi pochodzi z networking.hosts, bo RPi
# nie ma MagicDNS (rpi-tailscale).
#
# Granica zaufania: sesja T3 laptopa to powłoka i agenci na koncie głównym
# laptopa. Dlatego wąsko:
# - RPi: nowe połączenia przez tailscale0 otwiera tylko t3code (reguła
#   iptables owner); usługi WWW i konto główne RPi dostają odmowę.
# - Polityka tailnetu (panel Tailscale) celowo nie zawęża ruchu: każde
#   urządzenie łączy się z każdym. Granicę trzymają hosty: z RPi wychodzi
#   tylko t3code (wyżej), a laptop przyjmuje z tailnetu tylko porty Serve
#   i porty otwarte globalnie w nixos-fw (netfilter nodivert); sshd laptopa
#   z LAN-u i z tailnetu tylko od telefonu (nixos-ssh).
# - Laptop: z portem T3 desktop (słucha na 0.0.0.0, firewall go nie otwiera)
#   łączy się lokalnie tylko root (proxy tailscaled) i konto główne; inne
#   konta dostają odmowę (customBot.tailscaleServe.users).
# - Uwierzytelnia sam T3 (parowanie środowisk); poziom dostępu RPi wybiera się
#   przy parowaniu (approval-required: każdą zmianę zatwierdza się ręcznie).
# Ryzyko resztkowe: root albo konto t3code na RPi steruje sesjami T3 laptopa
# z poziomem dostępu z parowania.
#
# Jednorazowo: w T3 na RPi dodać środowisko https://nixos.<tailnet>
# i sparować je kodem z T3 laptopa. Wycofanie: usunąć sparowane środowisko
# w T3 laptopa.
#
# Sprawdzenie: na RPi `sudo -u t3code curl -sI https://nixos.<tailnet>`
# (odpowiada) i `curl -sI https://nixos.<tailnet>` jako nixos (odmowa),
# `sudo iptables -S OUTPUT | grep tailscale0`; na laptopie `tailscale serve
# status`, `sudo iptables -S OUTPUT | grep 3773`.
_:
let
  laptopHost = "nixos";
in
{
  flake.modules.nixos.nixos-t3code-laptop =
    { config, ... }:
    {
      # T3 Code desktop (desktop-ai) słucha na domyślnym 3773; gdy port jest
      # zajęty, bierze następny i Serve odpowiada 502.
      customBot.tailscaleServe."443" = {
        port = 3773;
        users = [ config.customBot.defaultUser ];
      };
    };

  flake.modules.nixos.rpi-t3code-laptop =
    { config, lib, ... }:
    let
      inherit (config.services.tailscale) interfaceName;
      t3User = config.systemd.services.t3code.serviceConfig.User;
      # Bez stanu NEW reguła odcięłaby też odpowiedzi w połączeniach
      # przychodzących z tailnetu (SSH). OUTPUT nie jest czyszczony przy
      # reloadzie firewalla, więc reguła jest najpierw usuwana.
      rule = "OUTPUT -o ${interfaceName} -m conntrack --ctstate NEW -m owner ! --uid-owner ${t3User} -j REJECT";
      commands = [
        "iptables"
        "ip6tables"
      ];
    in
    {
      networking = {
        hosts.${config.customTop.tailnet.laptop} = [ "${laptopHost}.${config.customTop.tailnet.domain}" ];

        firewall = {
          extraCommands = lib.concatMapStrings (cmd: ''
            ${cmd} -D ${rule} 2>/dev/null || true
            ${cmd} -A ${rule}
          '') commands;
          extraStopCommands = lib.concatMapStrings (cmd: ''
            ${cmd} -D ${rule} 2>/dev/null || true
          '') commands;
        };
      };
    };
}
