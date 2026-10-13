# Zasoby małego serwera (4 GB RAM, dysk SSD): swap w zRAM i 8 GB pliku na
# SSD, /tmp w RAM-ie, maksymalnie 2 równoległe buildy, częstsze GC sklepu
# Nix i bez dokumentacji /share/doc.
_: {
  flake.modules.nixos.rpi-resources = {
    boot = {
      kernel.sysctl."vm.swappiness" = 100;
      tmp.useTmpfs = true;
    };

    zramSwap.enable = true;
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 8192; # MiB
      }
    ];

    # Częstsze GC na małym dysku (nadpisuje mkDefault z base-nix).
    nix = {
      settings.max-jobs = 2;
      gc = {
        dates = "daily";
        options = "--delete-older-than 3d";
      };
    };

    # Serwer headless: bez /share/doc. Przy okazji nie buduje się
    # python3.11-doc (nixpkgs#499166), więc overlay python-docs-fix jest zbędny.
    documentation.doc.enable = false;
  };
}
