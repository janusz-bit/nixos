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

        # zswap, zRAM, sysctl i THP: modules/hosts/nixos/tuning.nix.
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

        # Bez ananicy-cpp (reguły CachyOS): przy cgroup v2 każda aplikacja
        # ma własny scope, a nice działa tylko wewnątrz jednej cgroup —
        # zmierzone: nice -4 vs +15 w osobnych scope'ach 50/50 CPU, w jednym
        # 91/9; ioclass ignoruje scheduler NVMe `none`. Za to ustawiał
        # Konsoli/Steamowi nice -4/16, przez co GameMode odmawiał renice
        # („Refused to renice … prio was (-4)”), a nixpkgs wymusza
        # cgroup_realtime_workaround = true (KWin i Xwayland w root cgroup).

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

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users = {
        ${config.customBot.defaultUser} = {
          initialPassword = "${config.customBot.defaultUser}";
          isNormalUser = true;
          description = "${config.customBot.defaultUser}";
          extraGroups = [
            "networkmanager"
            "wheel"
            "gamemode"
          ];
        };
        root.initialPassword = "root";
      };
    };

}
