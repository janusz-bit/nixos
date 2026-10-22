# Zasoby małego serwera (4 GB RAM, dysk SSD): swap w zRAM i 8 GB pliku na
# SSD, /tmp w RAM-ie, maksymalnie 2 równoległe buildy, częstsze GC sklepu
# Nix i bez dokumentacji /share/doc.
_: {
  flake.modules.nixos.rpi-resources = _: {
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

    nix = {
      settings.max-jobs = 2;
      # Częstsze GC na małym dysku (nadpisuje mkDefault z base-nix).
      gc = {
        dates = "daily";
        options = "--delete-older-than 3d";
      };
    };

    # Serwer headless nie potrzebuje /share/doc. Przy okazji nie buduje się
    # python3.11-doc (python311 z tools.nix), które pada na nixpkgs#499166
    # (zamknięty wpis w temporary-fixes.md; błąd wróci z dokumentacją).
    documentation.doc.enable = false;
  };
}
