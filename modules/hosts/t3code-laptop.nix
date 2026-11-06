# T3 Code z raspberry-pi-4 wysyła sesje na laptopa: serwer T3 na RPi (konto
# t3code, rpi-t3code) łączy się jako środowisko z T3 desktop laptopa, które
# Tailscale Serve wystawia w tailnecie pod https://nixos.<tailnet> (443 ->
# 127.0.0.1:3773). Nazwa laptopa na RPi pochodzi z networking.hosts, bo RPi
# nie ma MagicDNS (rpi-tailscale).
#
# Granica zaufania: sesja T3 laptopa to powłoka i agenci na koncie głównym
# laptopa, czyli znacznie więcej niż claude-remote i hermes-llm. Dlatego wąsko:
# - RPi: nowe połączenia przez tailscale0 otwiera tylko t3code (reguła
#   iptables owner); hermes (treści z internetu), usługi WWW i konto główne
#   RPi dostają odmowę.
# - Polityka tailnetu (panel Tailscale, Access controls): tag:rpi dochodzi
#   tylko do TCP 443 laptopa; reszta laptopa (sshd tylko z LAN-u) zostaje
#   zamknięta dla RPi.
# - Laptop: z portem T3 desktop (słucha na 0.0.0.0, firewall go nie otwiera)
#   łączy się lokalnie tylko root (proxy tailscaled) i konto główne;
#   claude-remote, hermes-llm i strata, konta używane z RPi, dostają odmowę
#   (customBot.tailscaleServe.users).
# - Uwierzytelnia sam T3 (parowanie środowisk); poziom dostępu RPi wybiera się
#   przy parowaniu (approval-required: każdą zmianę zatwierdza się ręcznie).
# Ryzyko resztkowe: root albo konto t3code na RPi steruje sesjami T3 laptopa
# z poziomem dostępu z parowania.
#
# Jednorazowo: w polityce tailnetu obok istniejącego grantu dla członków
#   "hosts": { "laptop": "<customTop.tailnet.laptop>" },
#   "grants": [ …, { "src": ["tag:rpi"], "dst": ["laptop"], "ip": ["tcp:443"] } ]
# potem w T3 na RPi dodać środowisko https://nixos.<tailnet> i sparować je
# kodem z T3 laptopa. Wycofanie: usunąć grant (T3 zostaje sparowany, ale nie
# dochodzi).
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
