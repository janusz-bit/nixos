{ inputs, ... }:
{
  flake.modules.nixos.nixos-packages =
    { pkgs, config, ... }:
    {
      environment.systemPackages = with pkgs; [
        vscode
        vscodium
        zed-editor
        kdePackages.partitionmanager
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
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
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent # self-improving agent AI (RLM)
        deepseek-harness # modular agent harness CLI (dsh) — flake.overlays.deepseek-harness
        losange
        freecad-qt6
        antigravity-ide-fhs
        antigravity-cli
      ];

      hardware.wooting.enable = true;

      programs = {
        # Install firefox.
        firefox.enable = true;

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
