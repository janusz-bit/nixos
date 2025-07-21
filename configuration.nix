# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:
{
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  specialisation.gaming.configuration = {
    boot.initrd.kernelModules = [
      "vfio_pci"
      "vfio"
      "vfio_iommu_type1"

      "amdgpu" # replace or remove with your device's driver as needed
    ];

    boot.kernelParams = [
      "amd_iommu=on"
      "iommu=pt"
      "amd_iommu=on"
      "vfio-pci.ids=10de:28e0,10de:22be"
    ];

    programs.virt-manager.enable = true;
    virtualisation.spiceUSBRedirection.enable = true;
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true;
        ovmf = {
          enable = true;
          packages = [
            (pkgs.OVMF.override {
              secureBoot = true;
              tpmSupport = true;
            }).fd
          ];
        };
      };
    };

    users.users.dinosaur.extraGroups = [
      "networkmanager"
      "wheel"
      "adbusers"
      "tss"
      "kvm"
    ] ++ [ "libvirtd" ];

  };

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.initrd.luks.devices."luks-ef3bce9a-7ce8-46d3-a929-741a683f123f".device =
    "/dev/disk/by-uuid/ef3bce9a-7ce8-46d3-a929-741a683f123f";
  networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  security.tpm2.enable = true;
  security.tpm2.pkcs11.enable = true; # expose /run/current-system/sw/lib/libtpm2_pkcs11.so
  security.tpm2.tctiEnvironment.enable = true; # TPM2TOOLS_TCTI and TPM2_PKCS11_TCTI env variables
  # users.users.dinosaur.extraGroups = [ "tss" ]; # tss group has access to TPM devices

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Enable networking
  networking.networkmanager.enable = true;
  # 1. Użyj systemd-resolved jako backendu DNS dla NetworkManagera
  # Zapewni to lokalny cache DNS i obsługę DNS-over-TLS (DoT).
  networking.networkmanager.dns = "dnsmasq";

  # 2. Skonfiguruj systemd-resolved
  services.resolved.extraConfig = ''
    # Serwery DNS używane do zapytań (Cloudflare, Quad9)
    DNS=8.8.8.8 8.8.4.4 1.1.1.1 1.0.0.1 9.9.9.9

    # Serwery zapasowe (Google)
    FallbackDNS=8.8.8.8 8.8.4.4

    # Włącz szyfrowanie DNS-over-TLS w trybie 'oportunistycznym'
    # (użyje szyfrowania, jeśli serwer je obsługuje)
    DNSOverTLS=opportunistic

    # Włącz walidację DNSSEC
    DNSSEC=allow-downgrade
  '';

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

  # Enable the X11 windowing system.
  # You can disable this if you're only using the Wayland session.
  # services.xserver.enable = true;

  # Enable the KDE Plasma Desktop Environment.
  services.displayManager.sddm.enable = true;
  services.desktopManager.plasma6.enable = true;

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "pl2";

  # Enable CUPS to print documents.
  services.printing = {
    enable = true;
    drivers = with pkgs; [
      gutenprint
      hplip
      splix
    ];
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
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

  # Enable touchpad support (enabled default in most desktopManager).
  # services.xserver.libinput.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.dinosaur = {
    isNormalUser = true;
    description = "dinosaur";
    extraGroups = [
      "networkmanager"
      "wheel"
      "adbusers"
      "tss"
      "kvm"
    ];
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "dinosaur";

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    kdePackages.kate
    nixfmt-rfc-style
    nixd
    # vscodium-fhs
    vscode-fhs
    git
    mangohud
    protonup-qt
    vlc
    discord
    heroic
    signal-desktop
    handbrake
    obsidian
    pandoc
    kdePackages.wallpaper-engine-plugin
    betterdiscordctl
    libreoffice-qt
    hunspell
    hunspellDicts.pl_PL

    neovim
    lazygit
    curl
    fzf
    ripgrep
    fd

    qbittorrent

    clamav
    clamtk

    python314Full

    unzip

    emacs

    nil

    wine64
    winetricks

    universal-android-debloater

    kdePackages.kcalc
    # libsForQt5.kdeconnect-kde

    vim
    nano

    htop

    # nodejs
    nil
    # cargo
    # rustc
    # rustfmt
    # rust-analyzer
    # clippy

    pinta
    gimp3

    # binutils
    # gdb
    # lldb
    # cmake
    # ninja
    # gnumake
    stremio

    # clang
    # gcc

    librewolf
    thunderbird

    virt-manager
    looking-glass-client

    unrar
    wine64
    proton-caller
    protontricks
    # proton-ge-bin

    brave
  ];

  # networking.nameservers = [
  #   "8.8.8.8" # Google
  #   "8.8.4.4" # Google
  #   "9.9.9.9" # Quad9
  # ];

  services.clamav.daemon.enable = true;
  services.clamav.updater.enable = true;

  fonts.packages = with pkgs; [ nerd-fonts._0xproto ];

  # Enable kwallet PAM integration for secure KDE wallet access via plasma6.
  security.pam.services.dinosaur.kwallet = {
    enable = true;
    package = pkgs.kdePackages.kwallet-pam;
    # forceRun = true;
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
      dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
      localNetworkGameTransfers.openFirewall = true; # Open ports in the firewall for Steam Local Network Game Transfers
      gamescopeSession.enable = true;
    };
    obs-studio = {
      enable = true;
      plugins = with pkgs.obs-studio-plugins; [
        wlrobs
        obs-backgroundremoval
        obs-pipewire-audio-capture
      ];
    };
    direnv.enable = true;
    firefox.enable = true;
    gamemode.enable = true;
    partition-manager.enable = true;
    kdeconnect.enable = true;
    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
      enableBrowserSocket = true;
      enableExtraSocket = true;
    };
  };

  environment.sessionVariables = {
    STEAM_EXTRA_COMPAT_TOOLS_PATHS = "~/.local/share/Steam/compatibilitytools.d";
  };

  programs.steam.extraCompatPackages = [
    pkgs.proton-ge-bin
  ];

  # services.asusd.package = pkgs.asusctl.overrideAttrs {
  #   src = builtins.fetchTree "gitlab:asus-linux/asusctl/685345d6567bc366e93bbc3d7321f9d9a719a7ed";
  # };
  services.supergfxd.enable = true;

  services.asusd.asusdConfig.text = ''
    (
        charge_control_end_threshold: 80,
        disable_nvidia_powerd_on_battery: true,
        ac_command: "",
        bat_command: "",
        platform_profile_linked_epp: true,
        platform_profile_on_battery: Quiet,
        change_platform_profile_on_battery: true,
        platform_profile_on_ac: Performance,
        change_platform_profile_on_ac: true,
        profile_quiet_epp: Power,
        profile_balanced_epp: BalancePower,
        profile_custom_epp: Performance,
        profile_performance_epp: Performance,
        ac_profile_tunings: {
            Balanced: (
                enabled: false,
                group: {},
            ),
            Quiet: (
                enabled: false,
                group: {},
            ),
            Performance: (
                enabled: true,
                group: {
                    PptPl1Spl: 55,
                    PptPl2Sppt: 75,
                    PptPl3Fppt: 80,
                },
            ),
        },
        dc_profile_tunings: {
            Performance: (
                enabled: true,
                group: {
                    PptPl1Spl: 55,
                    PptPl2Sppt: 75,
                    PptPl3Fppt: 80,
                },
            ),
            Quiet: (
                enabled: false,
                group: {},
            ),
            Balanced: (
                enabled: false,
                group: {},
            ),
        },
        armoury_settings: {
            NvTempTarget: 87,
            PanelOverdrive: 1,
            NvDynamicBoost: 25,
        },
    )
  '';

  hardware.nvidia.open = lib.mkForce true;

  services.syncthing = rec {
    enable = true;
    openDefaultPorts = true;
    user = "dinosaur";
    dataDir = "/home/${user}";
    configDir = "/home/${user}/.config/syncthing";
  };

  system.autoUpgrade = {
    enable = true;
    dates = "7d";

  };

  # programs.nix-ld.enable = true;
  # programs.nix-ld.libraries = with pkgs; [
  #   # Add any missing dynamic libraries for unpackaged
  #   # programs here, NOT in environment.systemPackages
  # ];

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  # hardware.graphics.enable32Bit = true;

  boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_15;

  boot.kernelPatches =
    [
    {
      name = "asus-patch-series.patch";
      patch = "${inputs.g14_patches}/6.15/0002-asus.patch";
    }
  ];

  programs.adb.enable = true;

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = {
  #   enable = true;
  #   enableSSHSupport = true;
  # };

  # List services that you want to enable:

  services.fail2ban.enable = true;
  # Enable the OpenSSH daemon.
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      UseDns = true;
      PasswordAuthentication = true;

    };
  };

  systemd.services.sshd.wantedBy = lib.mkForce [ ];

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 22 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?

}
