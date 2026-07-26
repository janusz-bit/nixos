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
      specialisation = {
        power-save.configuration = {
          powerManagement.cpuFreqGovernor = lib.mkForce "powersave";
          services.power-profiles-daemon.enable = lib.mkForce false;

          # TLP: pełne ustawienia oszczędzania energii
          services.tlp = {
            enable = lib.mkForce true;
            settings = {
              # CPU
              CPU_SCALING_GOVERNOR_ON_AC = "powersave";
              CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
              CPU_ENERGY_PERF_POLICY_ON_AC = "power";
              CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
              CPU_BOOST_ON_AC = 0;
              CPU_BOOST_ON_BAT = 0;
              SCHED_POWERSAVE_ON_AC = 1;
              SCHED_POWERSAVE_ON_BAT = 1;
              NMI_WATCHDOG = 0;
              # Platform
              PLATFORM_PROFILE_ON_AC = "low-power";
              PLATFORM_PROFILE_ON_BAT = "low-power";
              # PCIe / Runtime PM
              PCIE_ASPM_ON_AC = "powersave";
              PCIE_ASPM_ON_BAT = "powersave";
              RUNTIME_PM_ON_AC = "auto";
              RUNTIME_PM_ON_BAT = "auto";
              # USB
              USB_AUTOSUSPEND = 1;
              USB_BLACKLIST_WWAN = 1;
              # Audio
              SOUND_POWER_SAVE_ON_AC = 1;
              SOUND_POWER_SAVE_ON_BAT = 1;
              SOUND_POWER_SAVE_CONTROLLER = "Y";
              # Disk
              DISK_IDLE_SECS_ON_BAT = 2;
              # WiFi
              WIFI_PWR_ON_AC = "on";
              WIFI_PWR_ON_BAT = "on";
            };
          };

          # WiFi powersave (wymagane dla WIFI_PWR_* w TLP)
          networking.networkmanager.wifi.powersave = lib.mkForce true;

          # thermald: inteligentne zarządzanie temperaturą Intela (DPTF)
          services.thermald.enable = lib.mkForce true;

          # UPower: polityka procentowa + hibernacja przy krytycznym
          services.upower = {
            enable = true;
            usePercentageForPolicy = true;
            percentageLow = 20;
            percentageCritical = 10;
            percentageAction = 5;
            criticalPowerAction = "Hibernate";
          };

          # Kernel params: oszczędzanie energii (łączy się z resume= z base)
          boot.kernelParams = [
            "pcie_aspm=powersave"
            "i915.enable_dc=2"
            "i915.enable_fbc=1"
            "i915.enable_psr=1"
            "nvme_core.default_ps_max_latency_us=0"
            "usbcore.autosuspend=30"
            "nmi_watchdog=0"
          ];

          # Mniejszy swappiness (hibernacja na LUKS swap)
          boot.kernel.sysctl."vm.swappiness" = 10;

          # Logind: lid switch + idle suspend
          services.logind.settings.Login = {
            HandleLidSwitch = "suspend";
            HandleLidSwitchExternalPower = "suspend";
            HandleLidSwitchDocked = "ignore";
            IdleAction = "suspend";
            IdleActionSec = "1200";
          };

          # SCX scheduler: powersave mode
          services.scx.extraArgs = lib.mkForce [
            "--powersave"
          ];

          # Lenovo LOQ charge threshold (~80%)
          # UWAGA: sprawdź czy sysfs istnieje:
          #   cat /sys/class/power_supply/BAT0/charge_control_end_threshold
          # LOQ (ideapad_laptop) może wymagać conservation_mode zamiast progu
          services.udev.extraRules = ''
            ACTION=="add|change", SUBSYSTEM=="power_supply", KERNEL=="BAT0", RUN+="${pkgs.bash}/bin/sh -c 'echo 80 > /sys/class/power_supply/BAT0/charge_control_end_threshold'"
          '';
        };
        reverse-sync.configuration = {
          hardware.nvidia = {
            powerManagement.finegrained = false;
            prime = {
              offload.enable = false;
              offload.enableOffloadCmd = false;
              reverseSync.enable = true;
            };
          };
        };
        sync-mode.configuration = {
          hardware.nvidia = {
            powerManagement.finegrained = false;
            prime = {
              offload.enable = false;
              offload.enableOffloadCmd = false;
              sync.enable = true;

            };
          };
        };
      };
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.default
        self.overlays.brave-debloater

      ];
      boot.kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v3;
      environment.sessionVariables = {
        GAMEMODERUNEXEC = "env __NV_PRIME_RENDER_OFFLOAD=1 __VK_LAYER_NV_optimus=NVIDIA_only __GLX_VENDOR_LIBRARY_NAME=nvidia PROTON_ENABLE_WAYLAND=1 PROTON_FSR4_UPGRADE=1 PROTON_DLSS_UPGRADE=1 PROTON_XESS_UPGRADE=1";
      };
      boot.supportedFilesystems = [ "btrfs" ];
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

      # Working hibernation
      boot.resumeDevice = "/dev/mapper/swap";
      boot.kernelParams = [ "resume=/dev/mapper/swap" ];
      # Opcjonalnie, ale zalecane przy hibernacji na LUKS:
      # boot.initrd.systemd.enable = true;

      services.avahi.enable = true;
      services.avahi.nssmdns4 = true;
      services.btrfs.autoScrub.enable = true;
      services.flatpak.enable = true;

      services = {

        ananicy = {
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };

        scx.enable = true;
        scx.scheduler = "scx_lavd";
        scx.extraArgs = [
          "--performance"
        ];

        displayManager = {
          sddm.wayland.enable = true;
          sddm.enable = true;
          sddm.autoNumlock = true;
        };
        desktopManager.plasma6.enable = true;

        # Enable the X11 windowing system.
        # You can disable this if you're only using the Wayland session.
        xserver.enable = true;

        # Configure keymap in X11
        xserver.xkb = {
          layout = "pl";
          variant = "";
        };

        # Enable CUPS to print documents.
        printing.enable = true;

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

      environment.etc."kcminputrc".text = ''
        [Keyboard]
        NumLock=0
      '';
      systemd.tmpfiles.rules = [
        "d /home/${config.customBot.defaultUser}/.config 0755 ${config.customBot.defaultUser} ${config.customBot.defaultUser} -"
        "L+ /home/${config.customBot.defaultUser}/.config/kcminputrc - - - - /etc/kcminputrc"
      ];

      hardware = {
        bluetooth.enable = true;
      };

      hardware.enableAllFirmware = true;
      hardware.wirelessRegulatoryDatabase = true;
      services.fail2ban = {
        enable = true;
        maxretry = 5;
        ignoreIP = [
          "127.0.0.1/8"
          "192.168.1.0/24"
        ];
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
      i18n.defaultLocale = "pl_PL.UTF-8";

      i18n.extraLocaleSettings = {
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

      # Configure console keymap
      console.keyMap = "pl2";
      security = {
        pam.services.${config.customBot.defaultUser}.kwallet.enable = true;
        rtkit.enable = true;
      };
      systemd.settings.Manager = {
        DefaultLimitNOFILE = "524288";
      };
      security.pam.loginLimits = [
        {
          domain = "${config.customBot.defaultUser}";
          type = "hard";
          item = "nofile";
          value = "524288";
        }
      ];

      # Define a user account. Don't forget to set a password with ‘passwd’.
      users.users.${config.customBot.defaultUser} = {
        initialPassword = "${config.customBot.defaultUser}";
        isNormalUser = true;
        description = "${config.customBot.defaultUser}";
        extraGroups = [
          "networkmanager"
          "wheel"
          "gamemode"
        ];
      };
      users.users.root.initialPassword = "root";
    };

}
