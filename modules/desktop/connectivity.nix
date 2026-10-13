# Łączność stacji roboczej: NetworkManager (Wi-Fi bez oszczędzania energii,
# stały MAC), mDNS przez avahi, Bluetooth i firmware urządzeń (Wi-Fi, BT).
_: {
  flake.modules.nixos.desktop-connectivity = _: {
    networking.networkmanager = {
      enable = true;
      wifi.powersave = false;
      wifi.macAddress = "preserve";
    };

    services.avahi = {
      enable = true;
      nssmdns4 = true;
    };

    hardware = {
      bluetooth.enable = true;
      enableAllFirmware = true;
      wirelessRegulatoryDatabase = true;
      # facter domyślnie ustawia useDHCP na wykrytych interfejsach, co włącza
      # dhcpcd obok NetworkManagera (dwa klienty DHCP na enp8s0: zdublowane
      # trasy domyślne, konflikt DHCPv6). Adresy daje wyłącznie NetworkManager.
      facter.detected.dhcp.enable = false;
    };
  };
}
