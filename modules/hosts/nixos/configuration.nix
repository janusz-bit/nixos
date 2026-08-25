{ inputs, self, ... }:
{
  flake.modules.nixos.nixos-configuration =
    {
      config,
      pkgs,
      lib,
      ...
    }:

    {
      nixpkgs.overlays = [
        self.overlays.brave-debloater
        self.overlays.prime-agent
        self.overlays.deepseek-harness
      ];

      boot = {
        kernelPackages = pkgs.linuxPackages_cachyos-lto;
        supportedFilesystems = [ "btrfs" ];
        binfmt.emulatedSystems = [ "aarch64-linux" ];

        # Working hibernation
        resumeDevice = "/dev/mapper/swap";
        kernelParams = [ "resume=/dev/mapper/swap" ];
        # Opcjonalnie, ale zalecane przy hibernacji na LUKS:
        # boot.initrd.systemd.enable = true;
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
        fail2ban = {
          enable = true;
          maxretry = 5;
          ignoreIP = [
            "127.0.0.1/8"
            "192.168.1.0/24"
          ];
        };

        ananicy = {
          enable = false;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };

        displayManager = {
          sddm = {
            wayland.enable = true;
            enable = true;
            autoNumlock = true;
          };
        };
        desktopManager.plasma6.enable = true;

        # Enable the X11 windowing system.
        # You can disable this if you're only using the Wayland session.
        xserver = {
          enable = true;

          # Configure keymap in X11
          xkb = {
            layout = "pl";
            variant = "";
          };
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
          # If you want to use JACK applications, uncomment this
          #jack.enable = true;

          # use the example session manager (no others are packaged yet so this is enabled by default,
          # no need to redefine it in your config for now)
          #media-session.enable = true;
        };
      };

      hardware = {
        # Samsung ML-2160 printer (SPL driver via splix)
        printers = {
          ensurePrinters = [
            {
              name = "Samsung-ML-2160";
              location = "Home";
              deviceUri = "usb://Samsung/ML-2160";
              model = "samsung/ml2160.ppd";
            }
          ];
          ensureDefaultPrinter = "Samsung-ML-2160";
        };
        bluetooth.enable = true;
        enableAllFirmware = true;
        wirelessRegulatoryDatabase = true;
      };

      environment = {
        sessionVariables = {
          GAMEMODERUNEXEC = "env __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PROTON_ENABLE_WAYLAND=1 PROTON_FSR4_UPGRADE=1 PROTON_DLSS_UPGRADE=1 PROTON_XESS_UPGRADE=1";
        };

        etc."kcminputrc".text = ''
          [Keyboard]
          NumLock=0
        '';
      };

      systemd = {
        tmpfiles.rules = [
          "d /home/${config.customBot.defaultUser}/.config 0755 ${config.customBot.defaultUser} ${config.customBot.defaultUser} -"
          "L+ /home/${config.customBot.defaultUser}/.config/kcminputrc - - - - /etc/kcminputrc"
        ];

        settings.Manager = {
          DefaultLimitNOFILE = "524288";
        };
      };

      networking = {
        hostName = "nixos";
        networkmanager = {
          enable = true;
          wifi.powersave = false;
          wifi.macAddress = "preserve";
        };
        firewall.allowedUDPPorts = [ 5353 ];
      };

      # Set your time zone.
      time.timeZone = "Europe/Warsaw";

      # Select internationalisation properties.
      i18n = {
        defaultLocale = "pl_PL.UTF-8";
        extraLocaleSettings = {
          LC_ADDRESS = "pl_PL.UTF-8";
          LC_IDENTIFICATION = "pl_PL.UTF-8";
          LC_MEASUREMENT = "pl_PL.UTF-8";
          LC_MONETARY = "pl_PL.UTF-8";
          LC_NAME = "pl_PL.UTF-8";
          LC_NUMERIC = "pl_PL.UTF-8";
          LC_PAPER = "pl_PL.UTF-8";
          LC_TELEPHONE = "pl_PL.UTF-8";
          LC_TIME = "pl_PL.UTF-8";
        };
      };

      # Configure console keymap
      console.keyMap = "pl2";

      security = {
        pam = {
          services.${config.customBot.defaultUser}.kwallet.enable = true;
          loginLimits = [
            {
              domain = "${config.customBot.defaultUser}";
              type = "hard";
              item = "nofile";
              value = "524288";
            }
          ];
        };
        rtkit.enable = true;
      };

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
