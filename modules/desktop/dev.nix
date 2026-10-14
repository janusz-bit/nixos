# Narzędzia programistyczne: edytory, kompilatory (C/C++, cross do Windows
# z Wine do testów), Jupyter, klient Gitei (tea) oraz emulacja aarch64
# (binfmt) do budowania systemu RPi na tym komputerze. Zed na hybrydzie
# Intel + NVIDIA widzi tylko Vulkan Intela (tymczasowe, niżej).
#
# Sprawdzenie Zeda: temporary-fixes.md, punkt 4 (runtime_status dGPU przy
# starcie `zeditor` zostaje `suspended`).
_: {
  flake.modules.nixos.desktop-dev =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.hardware.nvidia) prime;
      # Zed przy starcie (wgpu, enumerate_adapters) tworzy instancję Vulkan,
      # a na hybrydzie Intel + NVIDIA (PRIME offload) ICD NVIDII budzi przy
      # tym dGPU z D3cold (zmierzone na RTX 5060: runtime_status suspended
      # -> active; opóźnia pierwsze okno), choć Zed renderuje na iGPU.
      # Loader filtruje ICD po nazwie manifestu przed dlopen: zostaje tylko
      # ANV (intel_icd.x86_64.json), bez intel_hasvk_icd, nvidia_icd i reszty
      # Mesy. Tylko dla Zeda: Steam/gry potrzebują Vulkana NVIDII. Zmienną
      # dziedziczą procesy z Zeda (terminal, taski, LSP), więc nvidia-offload
      # z terminala Zeda nie zobaczy Vulkana NVIDII; CUDA bez zmian.
      # Tymczasowe: temporary-fixes.md.
      zedIntelOnly = pkgs.symlinkJoin {
        inherit (pkgs.zed-editor) pname version meta;
        paths = [ pkgs.zed-editor ];
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        postBuild = ''
          wrapProgram $out/bin/zeditor \
            --set VK_LOADER_DRIVERS_SELECT ${lib.escapeShellArg "intel_icd*"}
        '';
      };
      zed = if prime.offload.enable && prime.intelBusId != "" then zedIntelOnly else pkgs.zed-editor;
    in
    {
      boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

      environment.systemPackages = with pkgs; [
        vscode
        vscodium
        zed
        sqlite
        # JupyterLab + notebook + ipykernel (metapakiet jupyter-all)
        jupyter-all
        bootdev-cli
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
      ];
    };
}
