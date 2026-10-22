# Narzędzia programistyczne: edytory, kompilatory (C/C++, cross do Windows
# z Wine do testów), Jupyter, klient Gitei (tea) oraz emulacja aarch64
# (binfmt) do budowania systemu RPi na tym komputerze.
#
# Sprawdzenie Zeda: runtime_status dGPU przy starcie `zeditor` zostaje `suspended`.
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
      # Tymczasowe (temporary-fixes.md nr 4): przy PRIME offload ICD NVIDII budzi
      # dGPU z D3cold już przy vkCreateInstance, choć Zed renderuje na iGPU. Loader
      # ładuje więc tylko ANV (intel_icd*). Tylko dla Zeda: zmienną dziedziczą też
      # procesy z niego (terminal, LSP), Steam i gry potrzebują Vulkana NVIDII.
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
        jupyter-all
        bootdev-cli
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
