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

          services = {
            power-profiles-daemon.enable = lib.mkForce false;

            # TLP: pełne ustawienia oszczędzania energii
            tlp = {
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
                # Bateria: conservation mode (Lenovo ideapad_laptop)
                # 1 = ON (~60-80% cap, hardware-level), 0 = OFF (charges to 100%)
                START_CHARGE_THRESH_BAT0 = 0; # dummy — required by TLP, ignored by ideapad driver
                STOP_CHARGE_THRESH_BAT0 = 1; # 1 = conservation mode ON
              };
            };

            # thermald: inteligentne zarządzanie temperaturą Intela (DPTF)
            thermald.enable = lib.mkForce true;

            # UPower: polityka procentowa + hibernacja przy krytycznym
            upower = {
              enable = true;
              usePercentageForPolicy = true;
              percentageLow = 20;
              percentageCritical = 10;
              percentageAction = 5;
              criticalPowerAction = "Hibernate";
            };

            # Logind: lid switch + idle suspend
            logind.settings.Login = {
              HandleLidSwitch = "suspend";
              HandleLidSwitchExternalPower = "suspend";
              HandleLidSwitchDocked = "ignore";
              IdleAction = "suspend";
              IdleActionSec = "1200";
            };

            # SCX scheduler: powersave mode
            scx.extraArgs = lib.mkForce [ "--powersave" ];
          };

          # WiFi powersave (wymagane dla WIFI_PWR_* w TLP)
          networking.networkmanager.wifi.powersave = lib.mkForce true;

          boot = {
            # Kernel params: oszczędzanie energii (łączy się z resume= z base)
            kernelParams = [
              "pcie_aspm=powersave"
              "i915.enable_dc=2"
              "i915.enable_fbc=1"
              "i915.enable_psr=1"
              "nvme_core.default_ps_max_latency_us=0"
              "usbcore.autosuspend=30"
              "nmi_watchdog=0"
            ];

            # Mniejszy swappiness (hibernacja na LUKS swap)
            kernel.sysctl."vm.swappiness" = 10;
          };
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

        # PCI passthrough (VFIO): RTX 5060 Laptop GPU -> VM
        # wg https://wiki.nixos.org/wiki/PCI_passthrough
        # GPU: 01:00.0 VGA [10de:2d59] + 01:00.1 audio [10de:22eb] (facter.json).
        # Host zostaje na iGPU Intel (wyświetlacz), dGPU przechodzi do VM.
        # UWAGA: kernelParams/initrd wymagają REBOOT (sam switch nie przeładuje jądra).
        gpu-passthrough.configuration = {
          # facter automatycznie dodałby "nvidia" do boot.initrd.kernelModules,
          # a nixpkgs sortuje tę listę alfabetycznie (typ attrNamesToTrue),
          # więc nvidia wiązałby GPU PRZED vfio_pci. Wyłączamy auto-detekcję
          # grafiki; i915 dla iGPU hosta dodajemy jawnie poniżej.
          hardware.facter.detected.graphics.enable = false;

          boot = {
            # Moduły VFIO w initrd (muszą zająć GPU przed jakimkolwiek
            # sterownikiem GPU) + i915 dla iGPU hosta.
            initrd.kernelModules = [
              "vfio_pci"
              "vfio"
              "vfio_iommu_type1"
              "i915"
            ];
            # IOMMU + device IDs przejmowane przez vfio-pci (VGA + HDMI audio GPU)
            kernelParams = [
              "intel_iommu=on"
              "vfio-pci.ids=10de:2d59,10de:22eb"
            ];
            # Zabezpieczenie: nvidia nie może związać GPU w runtime
            # (np. po resume z hibernacji / PCI rescan)
            blacklistedKernelModules = [
              "nvidia"
              "nvidia_modeset"
              "nvidia_uvm"
              "nvidia_drm"
            ];
          };

          # GPU nie jest własnością hosta: X startuje na iGPU (modesetting),
          # prime offload i power management NVIDII wyłączone.
          services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
          hardware.nvidia = {
            powerManagement.enable = lib.mkForce false;
            powerManagement.finegrained = lib.mkForce false;
            prime = {
              offload.enable = lib.mkForce false;
              offload.enableOffloadCmd = lib.mkForce false;
            };
          };

          # libvirtd + QEMU/OVMF (UEFI) + TPM (swtpm) wg wiki
          virtualisation = {
            spiceUSBRedirection.enable = true;
            libvirtd = {
              enable = true;
              qemu = {
                package = pkgs.qemu_kvm;
                runAsRoot = true;
                swtpm.enable = true;
              };
            };
          };
          programs.virt-manager.enable = true;

          # Użytkownik może zarządzać VM bez roota
          users.users.${config.customBot.defaultUser}.extraGroups = [ "libvirtd" ];
        };
      };
      nixpkgs.overlays = [
        inputs.nix-cachyos-kernel.overlays.default
        self.overlays.brave-debloater
        self.overlays.prime-agent
      ];

      boot = {
        kernelPackages = pkgs.cachyosKernels.linuxPackages-cachyos-latest-lto-x86_64-v3;
        supportedFilesystems = [ "btrfs" ];
        binfmt.emulatedSystems = [ "aarch64-linux" ];

        # Working hibernation
        resumeDevice = "/dev/mapper/swap";
        kernelParams = [ "resume=/dev/mapper/swap" ];
        # Opcjonalnie, ale zalecane przy hibernacji na LUKS:
        # boot.initrd.systemd.enable = true;
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
          enable = true;
          package = pkgs.ananicy-cpp;
          rulesProvider = pkgs.ananicy-rules-cachyos;
        };

        scx = {
          enable = true;
          scheduler = "scx_lavd";
          extraArgs = [ "--performance" ];
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
