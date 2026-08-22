_: {
  flake.modules.nixos.nixos-packages =
    { pkgs, config, ... }:
    {
      environment.systemPackages = with pkgs; [
        zed-editor
        kdePackages.partitionmanager
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
        pkgs.proton-cachyos_x86_64_v3 # z chaotic-nyx (binary cache, bez własnego builda)
        # proton-ge-bin
        # niri
        alacritty
        sqlite
        brave
        libreoffice-qt
        kdePackages.qrca
        signal-desktop
        element-desktop
        (prismlauncher.override {
          # Add binary required by some mod
          additionalPrograms = [ ffmpeg ];

          # Change Java runtimes available to Prism Launcher
          jdks = [
            graalvmPackages.graalvm-ce
            zulu8
            zulu17
            zulu
          ];
        })
        lutris
        bootdev-cli
        kdePackages.kcalc
        nextcloud-client
        haruna
        kdePackages.elisa
        sbctl
        joplin-desktop
        # bitwarden-desktop
        trilium-desktop
        foliate
        ungoogled-chromium
        # Compilers & build tools
        cmake
        ninja
        clang
        pkgs.pkgsCross.mingwW64.buildPackages.gcc
        wine64
        clang-tools
        lldb
        boost
        tea
        kdePackages.kdenlive
        opencode
        prime-agent # self-improving agent AI (RLM) — flake.overlays.prime-agent
        deepseek-harness # modular agent harness CLI (dsh) — flake.overlays.deepseek-harness
        losange
        freecad-qt6
        antigravity-ide-fhs
      ];

      hardware.wooting.enable = true;

      programs = {
        # Install firefox.
        firefox.enable = true;

        steam = {
          enable = true;
          remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
          dedicatedServer.openFirewall = true; # Open ports for Source Dedicated Server hosting
          extraCompatPackages = [
            pkgs.proton-cachyos_x86_64_v3 # z chaotic-nyx
            pkgs.proton-ge-bin
          ];
        };

        gamemode.enable = true; # for performance mode

        obs-studio = {
          enable = true;

          # optional Nvidia hardware acceleration
          package = pkgs.obs-studio.override {
            cudaSupport = true;
          };

          plugins = with pkgs.obs-studio-plugins; [
            wlrobs
            obs-backgroundremoval
            obs-pipewire-audio-capture
            obs-gstreamer
            obs-vkcapture
          ];
        };
      };

      # Mullvad split upstream: pkgs.mullvad = daemon (module default),
      # pkgs.mullvad-vpn = GUI only, enabled via gui.enable.
      services = {
        mullvad-vpn = {
          enable = true;
          gui.enable = true;
        };

        syncthing = {
          enable = true;
          user = "${config.customBot.defaultUser}";
          dataDir = "/home/${config.customBot.defaultUser}/Sync";
          configDir = "/home/${config.customBot.defaultUser}/.config/syncthing";
          openDefaultPorts = true;
        };
      };
    };
}
