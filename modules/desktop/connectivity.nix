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
      # facter włącza useDHCP na wykrytych interfejsach, czyli dhcpcd obok
      # NetworkManagera (zdublowane trasy domyślne, konflikt DHCPv6).
      facter.detected.dhcp.enable = false;
    };
  };
}
