# Sprzęt laptopa Lenovo LOQ 15IRX10: i5-13450HX (Intel UHD Graphics) + RTX
# 5060 Laptop w PRIME offload (domyślnie iGPU, `nvidia-offload <cmd>` na dGPU),
# otwarty sterownik NVIDIA z runtime PM i Dynamic Boost, raport nixos-facter.
#
# Fakty o GPU są tylko tutaj: moduły desktop-* i gaming-* czytają
# hardware.nvidia.enabled i hardware.nvidia.prime.* (ollama-cuda, OBS z CUDA,
# NODEVICE_SELECT w Steamie, zmienne PRIME w GAMEMODERUNEXEC, ICD tylko
# Intela w Zedzie), więc stacja bez NVIDII nie dostaje buildów CUDA ani
# ustawień PRIME. Resztę sprzętu (m.in. moduły initrd) opisuje facter.json
# obok, wygenerowany przez nixos-facter na tej maszynie. Moduł importuje też
# poprawki Lenovo, cechy x86-64-v3 i profile nixos-hardware.
# Nowa maszyna dostaje własny katalog modules/hardware/<model>/ jak ten
# (default.nix + facter.json; procedura: README.md, "Adding a host").
#
# Sprawdzenie: `cat /sys/bus/pci/devices/0000:01:00.0/power/{control,runtime_status}`
# w spoczynku daje auto i suspended (dGPU w D3cold).
{ inputs, self, ... }:
{
  flake.modules.nixos.hardware-LOQ-15IRX10 =
    {
      config,
      lib,
      ...
    }:
    {
      # Pakiety CUDA (ollama-cuda, OBS z cudaSupport) nie są w cache.nixos.org
      # i kompilują się lokalnie — tylko dla tej karty (Blackwell, sm_120)
      # zamiast dla całej listy architektur.
      nixpkgs.config.cudaCapabilities = [ "12.0" ];

      # Włącza sterownik NVIDIA także bez serwera X (Wayland).
      services.xserver.videoDrivers = [ "nvidia" ];

      # See temporary-fixes.md: reguły finegrained z nixpkgs włączają runtime
      # PM tylko na ACTION=="bind"; tu dGPU zostawało z power/control = on
      # (domyślne PCI), więc nigdy nie zasypiało (D3cold). Jak 71-nvidia.rules
      # z CachyOS: także przy coldplug ("add"), gdy sterownik jest już zbindowany.
      services.udev.extraRules = lib.mkIf config.hardware.nvidia.powerManagement.finegrained ''
        ACTION=="add|bind", SUBSYSTEM=="pci", DRIVERS=="nvidia", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", TEST=="power/control", ATTR{power/control}="auto"
      '';

      hardware = {
        facter.reportPath = ./facter.json;
        graphics = {
          enable = true;
          enable32Bit = true;
        };
        nvidia = {
          modesetting.enable = true;
          powerManagement.enable = true;
          powerManagement.finegrained = lib.mkDefault true;
          open = true;
          nvidiaSettings = true;
          # Dynamic Boost (nvidia-powerd): z firmware przesuwa budżet mocy z CPU
          # na GPU w grach GPU-bound — bez demona GPU nie dostaje watów Dynamic
          # Boost wliczonych w maksymalne TGP laptopa. Kontrola:
          # `nvidia-smi -q -d POWER` pod obciążeniem
          # (Current Power Limit rośnie ponad bazowe TGP). Sprawdzone
          # 2026-09-29: nvidia-powerd nie blokuje D3cold (runtime_status =
          # suspended, także z monitorem na DisplayPort).
          dynamicBoost.enable = true;
          package = config.boot.kernelPackages.nvidiaPackages.latest;
          prime = {
            offload.enableOffloadCmd = lib.mkDefault true;
            sync.enable = lib.mkDefault false;

            intelBusId = "PCI:0:2:0";
            nvidiaBusId = "PCI:1:0:0";
          };
        };
      };

      imports = [
        self.modules.nixos.hardware-lenovo
        self.modules.nixos.hardware-x86-64-v3
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.nixos-hardware.nixosModules.common-pc-laptop
        inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
      ];
    };

}
