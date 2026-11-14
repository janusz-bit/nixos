# SSH na laptopa z telefonu przez tailnet: port sshd otwarty na tailscale0
# tylko dla adresów tailnetu telefonu (customTop.tailnet.phone), a klucz
# telefonu w authorized_keys konta głównego z `from=` tych samych adresów.
# Reszta tailnetu (także RPi, mniej zaufany) do sshd laptopa nie dochodzi;
# z domowego LAN-u SSH zostaje jak w base-ssh-lan. lockdown zatrzymuje
# tailscaled, więc odcina też to wejście.
#
# Adresy tailnetu są stałe, dopóki telefon nie zostanie usunięty z tailnetu
# i zalogowany od nowa; wtedy nowe adresy z `tailscale ip <telefon>` wpisać
# w modules/args.nix.
#
# Sprawdzenie: `sudo iptables -S nixos-fw | grep tailscale0`,
# `sudo ip6tables -S nixos-fw | grep tailscale0`, z telefonu (Tailscale
# włączony) `ssh dinosaur@nixos.<tailnet>`.
_: {
  flake.modules.nixos.nixos-ssh =
    { config, lib, ... }:
    let
      inherit (config.customTop) keys;
      inherit (config.customTop.tailnet) phone;
      interface = config.services.tailscale.interfaceName;
      port = toString (lib.head config.services.openssh.ports);
      rule = cmd: address: ''
        ${cmd} -A nixos-fw -i ${interface} -s ${address} -p tcp --dport ${port} -j nixos-fw-accept
      '';
    in
    {
      # nixos-fw jest czyszczony przy każdym reloadzie firewalla, więc reguły
      # się nie mnożą (jak w base-ssh-lan).
      networking.firewall.extraCommands = rule "iptables" phone.ipv4 + rule "ip6tables" phone.ipv6;

      users.users.${config.customBot.defaultUser}.openssh.authorizedKeys.keys = [
        ''from="${phone.ipv4},${phone.ipv6}" ${keys.users.phone}''
      ];
    };
}
