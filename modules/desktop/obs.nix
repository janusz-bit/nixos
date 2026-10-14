# OBS Studio z wtyczkami (przechwytywanie Wayland/PipeWire/Vulkan, usuwanie
# tła). Z NVIDIĄ (hardware.nvidia.enabled) wariant z CUDA: koder NVENC i
# akceleracja usuwania tła. Pakiety CUDA nie są w cache.nixos.org i budują
# się lokalnie (cudaCapabilities ustawia moduł sprzętu), więc bez NVIDII
# zostaje zwykły pakiet z cache.
_: {
  flake.modules.nixos.desktop-obs =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      programs.obs-studio = {
        enable = true;
        package = lib.mkIf config.hardware.nvidia.enabled (
          pkgs.obs-studio.override { cudaSupport = true; }
        );
        plugins = with pkgs.obs-studio-plugins; [
          wlrobs
          obs-backgroundremoval
          obs-pipewire-audio-capture
          obs-gstreamer
          obs-vkcapture
        ];
      };
    };
}
