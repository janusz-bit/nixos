# Agenci Brulionu z laptopa dla telefonu: aplikacja Brulion (desktop-brulion)
# z włączonym „Udostępnij agentów telefonowi” uruchamia jako użytkownik
# `brulion-cli acp serve --tailscale --port 8790` na adresie tailnetu
# laptopa, a Brulion na telefonie łączy się z http://nixos.<tailnet>:8790.
# Port jest otwarty na tailscale0 tylko dla adresów tailnetu telefonu
# (customTop.tailnet.phone), jak sshd w nixos-ssh: agent to Claude Code
# z powłoką na koncie głównym, a `--tailscale` paruje urządzenia własnego
# loginu tailnetu bez kodu, więc reszta tailnetu (także RPi, mniej zaufany)
# nie może do niego dojść. lockdown zatrzymuje tailscaled, więc odcina też
# to wejście.
#
# Port 8790 to domyślny port udostępniania w ustawieniach aplikacji (nie
# z Nixa); zmiana tam wymaga zmiany tutaj.
#
# Sprawdzenie: `sudo iptables -S nixos-fw | grep 8790`, `ss -ltnp | grep 8790`,
# z telefonu (Tailscale włączony) Brulion Ustawienia -> Rozszerzenia ->
# Agenci AI -> agent „Na nixos” -> Dodaj.
_: {
  flake.modules.nixos.nixos-brulion-agent =
    { config, ... }:
    let
      inherit (config.customTop.tailnet) phone;
      interface = config.services.tailscale.interfaceName;
      rule = cmd: address: ''
        ${cmd} -A nixos-fw -i ${interface} -s ${address} -p tcp --dport 8790 -j nixos-fw-accept
      '';
    in
    {
      # nixos-fw jest czyszczony przy każdym reloadzie firewalla, więc reguły
      # się nie mnożą (jak w nixos-ssh).
      networking.firewall.extraCommands = rule "iptables" phone.ipv4 + rule "ip6tables" phone.ipv6;
    };
}
