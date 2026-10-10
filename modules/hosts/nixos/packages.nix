{ inputs, ... }:
{
  flake.modules.nixos.nixos-packages =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      user = config.customBot.defaultUser;
      home = config.users.users.${user}.home;
      # Hermes Desktop (Electron) z flake hermes-agent; stan w ~/.hermes
      hermes-desktop = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.desktop;
      # Zed przy starcie (wgpu, enumerate_adapters) tworzy instancję Vulkan,
      # a ICD NVIDII budzi przy tym RTX 5060 z D3cold (zmierzone: runtime_status
      # suspended -> active; opóźnia pierwsze okno), choć Zed renderuje na iGPU.
      # Loader filtruje ICD po nazwie manifestu przed dlopen: zostaje tylko
      # ANV (intel_icd.x86_64.json), bez intel_hasvk_icd, nvidia_icd i reszty
      # Mesy. Tylko dla Zeda: Steam/gry potrzebują Vulkana NVIDII. Zmienną
      # dziedziczą procesy z Zeda (terminal, taski, LSP), więc nvidia-offload
      # z terminala Zeda nie zobaczy Vulkana NVIDII; CUDA bez zmian.
      # Tymczasowe: temporary-fixes.md.
      zed-editor-igpu = pkgs.symlinkJoin {
        inherit (pkgs.zed-editor) pname version meta;
        paths = [ pkgs.zed-editor ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram $out/bin/zeditor \
            --set VK_LOADER_DRIVERS_SELECT ${lib.escapeShellArg "intel_icd*"}
        '';
      };
    in
    {
      environment.systemPackages = with pkgs; [
        vscode
        vscodium
        zed-editor-igpu
        kdePackages.partitionmanager
        qbittorrent-enhanced
        heroic # install heroic launcher
        protonup-qt
        vesktop
        vlc
        tor-browser
        alacritty
        sqlite
        libreoffice-qt
        kdePackages.qrca
        # Waywallen — dynamiczne tapety (zamiennik Wallpaper Engine Plugin).
        # Nie wymaga Steama/Protonu; tapety Wallpaper Engine przez wbudowany
        # plugin open-wallpaper-engine. Ustawianie tapet: aplikacja waywallen.
        # waywallen* i bootdev-cli to pakiety lokalne z overlaya
        # local-packages (modules/packages/packages.nix).
        waywallen
        waywallen-kde-plugin
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
        # Kleopatra — GUI do kluczy OpenPGP/S/MIME. gpg-agent (z pinentry-qt
        # od plasma6) włącza już base-ssh (programs.gnupg.agent).
        kdePackages.kleopatra
        # KRecorder — dyktafon (nagrywanie dźwięku z mikrofonu, lista nagrań,
        # odtwarzacz; aplikacja KDE na Kirigami).
        kdePackages.krecorder
        # Narzędzia do rysowania (odpowiednik Windows Paint):
        # KolourPaint — prosty paint z KDE; Pinta — jak Paint.NET
        # (warstwy, historia zmian, efekty).
        kdePackages.kolourpaint
        pinta
        # JupyterLab + notebook + ipykernel (metapakiet jupyter-all)
        jupyter-all
        nextcloud-client
        haruna
        kdePackages.elisa
        sbctl
        joplin-desktop
        trilium-desktop
        foliate
        ungoogled-chromium
        # Compilers & build tools
        cmake
        ninja
        clang
        pkgsCross.mingwW64.buildPackages.gcc
        wine64
        clang-tools
        lldb
        boost
        tea
        kdePackages.kdenlive
        opencode
        losange
        freecad-qt6
        antigravity-ide-fhs
        antigravity-cli
        hermes-desktop
        # chatgpt z nixpkgs usunięty: aarch64-darwin-only; ChatGPT Desktop dla
        # x86_64-linux (deb) jest w modules/hosts/nixos/ai.nix z llm-agents.nix
      ];

      hardware.wooting.enable = true;

      programs = {
        # Install firefox.
        firefox.enable = true;

        # Plasma Browser Integration — rozszerzenie "Plasma Integration"
        # (plasma-browser-integration@kde.org, w Helium) łączy się z hostem
        # przez native messaging. Moduł plasma6 w nixpkgs ustawia już
        # enablePlasmaBrowserIntegration + pakiet, ale manifesty hosta w
        # /etc/chromium i /etc/opt/chrome wystawia dopiero ta opcja —
        # NICZEGO nie instaluje, pisze tylko polityki i manifesty do /etc.
        # Bez tego Helium i ungoogled-chromium pokazują błąd
        # "Specified native messaging host not found." Firefox jest podpięty
        # przez moduł plasma6 (programs.firefox.nativeMessagingHosts).
        chromium.enable = true;

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
          inherit user;
          dataDir = "${home}/Sync";
          configDir = "${home}/.config/syncthing";
          openDefaultPorts = true;
        };
      };
    };
}
