{ inputs, customTop, ... }:
{
  flake.modules.nixos.nixos-configuration =
    {
      config,
      pkgs,
      ...
    }:

    {
      nixpkgs.overlays = [
        # pinned = ten sam nixpkgs, którym Hydra autora buduje kernele, więc
        # kernel przychodzi z cache attic.xuyh0120.win/lantian (customTop.cache)
        # zamiast kompilować się lokalnie po każdym bumpie naszego nixpkgs.
        inputs.nix-cachyos-kernel.overlays.pinned
      ];

      boot = {
        # Kernel z https://github.com/xddxdd/nix-cachyos-kernel (gałąź release)
        # latest-lto + x86_64-v3 (i5-13450HX wspiera v3, nie avx512).
        kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-bore-lto-x86_64-v3;
        supportedFilesystems = [ "btrfs" ];
        binfmt.emulatedSystems = [ "aarch64-linux" ];

        # Working hibernation (resumeDevice sam dodaje parametr resume=)
        resumeDevice = "/dev/mapper/swap";

        # Kernel CachyOS ma CONFIG_ZSWAP_DEFAULT_ON=y, a moduł boot.zswap
        # przy enable = false nic nie wyłącza: zswap kompresowałby strony
        # przed zapisem do zRAM (podwójna kompresja, zmarnowany CPU).
        kernelParams = [ "zswap.enabled=0" ];

        # Strojenie pod swap w zRAM (jak 30-zram.rules i 70-cachyos-settings
        # z CachyOS): dekompresja z RAM jest tańsza niż ponowny odczyt page
        # cache z dysku, a readahead swapu (8 stron) nie ma sensu dla zRAM.
        kernel.sysctl = {
          "vm.swappiness" = 150;
          "vm.page-cluster" = 0;
        };
      };

      # Optymalizacja pamięci: zRAM ze zstd (priorytet 100 > swap dyskowy -2).
      # Dysk NVMe LUKS swap (/dev/mapper/swap) pozostaje dedykowany pod hibernację.
      zramSwap = {
        enable = true;
        algorithm = "zstd";
        priority = 100;
        memoryPercent = 50;
      };

      services = {
        avahi = {
          enable = true;
          nssmdns4 = true;
        };
        btrfs.autoScrub.enable = true;
        flatpak.enable = true;

        # SSH tylko z domowego LAN-u (reguła firewall niżej) — nie z każdej
        # sieci, do której podłączy się laptop.
        openssh.openFirewall = false;

        # Sched-ext (BPF scheduler) — scx_lavd zoptymalizowany pod gry i hybrydowe rdzenie P+E
        scx = {
          enable = false;
          scheduler = "scx_lavd";
          extraArgs = [ "--performance" ];
        };

        # Ananicy-cpp z regułami CachyOS (git) — dynamiczne priorytety procesów gier i PipeWire
        ananicy = {
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };

        # Plasma 6 + SDDM na Waylandzie — serwer X nie jest potrzebny
        # (XWayland uruchamia KWin); opcje xkb działają bez xserver.enable.
        displayManager = {
          sddm = {
            wayland.enable = true;
            enable = true;
            autoNumlock = true;
          };
        };
        desktopManager.plasma6.enable = true;

        xserver.xkb = {
          layout = "pl";
          variant = "";
        };

        # Enable CUPS to print documents.
        printing = {
          enable = true;
          drivers = [ pkgs.splix ];
          # Domyślnie włączany razem z avahi: demon root bez sandboxa, który
          # tworzy kolejki z ogłoszeń DNS-SD z każdej sieci (wejście łańcucha
          # RCE CUPS z 2024). Drukarki IPP Everywhere CUPS 2.4 i okno
          # drukowania Plasmy wykrywają i bez niego.
          browsed.enable = false;
        };

        # Enable sound with pipewire.
        pulseaudio.enable = false;
        pipewire = {
          enable = true;
          alsa.enable = true;
          alsa.support32Bit = true;
          pulse.enable = true;
        };
      };

      hardware = {
        bluetooth.enable = true;
        enableAllFirmware = true;
        wirelessRegulatoryDatabase = true;
      };

      environment = {
        sessionVariables = {
          GAMEMODERUNEXEC = "env __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PROTON_ENABLE_WAYLAND=1 PROTON_ENABLE_NGX_UPDATER=1 PROTON_FSR4_UPGRADE=1 PROTON_DLSS_UPGRADE=1 PROTON_XESS_UPGRADE=1";
        };

        # Num Lock włączony w sesji Plasmy (0 = włącz). KDE czyta domyślne
        # konfiguracje z XDG_CONFIG_DIRS, czyli /etc/xdg — nie z /etc.
        etc."xdg/kcminputrc".text = ''
          [Keyboard]
          NumLock=0
        '';
      };

      # Bez oomd na zakresach użytkownika wyciek pamięci (przeglądarka, gra,
      # model LLM na CPU, build CUDA) zapełniał 16 GB zRAM i 36 GB swapu, a
      # pulpit stał minutami, zanim zadziałał OOM-killer jądra. oomd zabija
      # najgorszy zakres aplikacji pod trwałą presją, nie całą sesję.
      systemd.oomd.enableUserSlices = true;

      # Laptop interaktywny (gry, Plasma): lokalne buildy (m.in. CUDA)
      # ustępują pulpitowi — zalecenie z dokumentacji opcji dla komputerów
      # używanych interaktywnie.
      nix = {
        daemonCPUSchedPolicy = "idle";
        daemonIOSchedClass = "idle";
      };

      networking = {
        hostName = "nixos";
        networkmanager = {
          enable = true;
          wifi.powersave = false;
          wifi.macAddress = "preserve";
        };
        # iptables (networking.nftables jest wyłączone)
        firewall.extraCommands = ''
          iptables -A nixos-fw -p tcp -s ${customTop.lan.subnet} --dport 22 -j nixos-fw-accept
        '';
      };

      # facter domyślnie ustawia useDHCP na wykrytych interfejsach, co włącza
      # dhcpcd obok NetworkManagera (dwa klienty DHCP na enp8s0: zdublowane
      # trasy domyślne, konflikt DHCPv6). Adresy daje wyłącznie NetworkManager.
      hardware.facter.detected.dhcp.enable = false;

      # Set your time zone.
      time.timeZone = "Europe/Warsaw";

      i18n.defaultLocale = "pl_PL.UTF-8";

      # Configure console keymap
      console.keyMap = "pl2";

      # KWallet przez PAM (login/sddm/kde) konfiguruje moduł plasma6.
      security.rtkit.enable = true;

      # Konta tworzone z zablokowanym hasłem: install-system ustawia hasła
      # (passwd) zaraz po nixos-install. Dawne jawne initialPassword
      # (root/root, użytkownik = nazwa) zostawały publiczne w repo, gdyby
      # instalację przerwano przed tym krokiem.
      users.users = {
        ${config.customBot.defaultUser} = {
          initialHashedPassword = "!";
          isNormalUser = true;
          description = "${config.customBot.defaultUser}";
          extraGroups = [
            "networkmanager"
            "wheel"
            "gamemode"
          ];
        };
        root.initialHashedPassword = "!";
      };
    };

}
