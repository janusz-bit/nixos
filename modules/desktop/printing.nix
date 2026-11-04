# Drukowanie przez CUPS. Sterowniki: splix (drukarki Samsung, protokół SPL)
# i brlaser (Brother; zawiera wpis HL-L1232W, używany przy podłączeniu USB).
#
# Brother HL-L1232W po Wi-Fi drukuje bez sterownika, przez AirPrint/IPP
# Everywhere: cups-filters i ghostscript CUPS dostaje zawsze, wyszukiwanie
# po mDNS zapewnia avahi, a GUI (print-manager) dociąga moduł plasma6 razem
# z services.printing. Kolejki CUPS są stanem /var/lib/cups (nixpkgs nie ma
# deklaratywnych kolejek), więc drukarkę dodaje się raz, włączoną i w sieci:
# Ustawienia systemowe -> Drukarki (sterownik wybierany automatycznie).
# Sprawdzenie: lpstat -p i strona testowa w print-managerze.
_: {
  flake.modules.nixos.desktop-printing =
    { pkgs, ... }:
    {
      services.printing = {
        enable = true;
        drivers = [
          pkgs.brlaser
          pkgs.splix
        ];
      };
    };
}
