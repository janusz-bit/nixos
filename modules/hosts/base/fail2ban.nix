# fail2ban dla hostów z SSH dostępnym z sieci (nixos, raspberry-pi-4).
# Celowo bez całej podsieci LAN w ignoreIP: na laptopie „domowa” podsieć
# pokrywa się z sieciami hotelowymi/kawiarnianymi. RPi (stała sieć domowa)
# dopisuje customTop.lan.subnet u siebie.
_: {
  flake.modules.nixos.fail2ban = _: {
    services.fail2ban = {
      enable = true;
      maxretry = 5;
      ignoreIP = [
        "127.0.0.1/8"
        "::1"
      ];
    };
  };
}
