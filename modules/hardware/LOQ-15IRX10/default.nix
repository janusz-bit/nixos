# Sprzęt laptopa Lenovo LOQ 15IRX10: i5-13450HX (Intel UHD Graphics) + RTX
# 5060 Laptop w PRIME offload (domyślnie iGPU, `nvidia-offload <cmd>` na dGPU),
# otwarty sterownik NVIDIA z runtime PM i Dynamic Boost, raport nixos-facter.
#
# Fakty o GPU są tylko tutaj: moduły desktop-* i gaming-* czytają
# hardware.nvidia.enabled i hardware.nvidia.prime.*, więc stacja bez NVIDII nie
# dostaje buildów CUDA ani ustawień PRIME. Resztę sprzętu (m.in. moduły initrd)
# opisuje facter.json, wygenerowany przez nixos-facter na tej maszynie.
#
# Sprawdzenie: `cat /sys/bus/pci/devices/0000:01:00.0/power/{control,runtime_status}`
# w spoczynku daje auto i suspended (dGPU w D3cold), a
# /proc/driver/nvidia/gpus/0000:01:00.0/power pokazuje
# `Runtime D3 status: Enabled (fine-grained)`.
{ inputs, self, ... }:
{
  flake.modules.nixos.hardware-LOQ-15IRX10 =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.hardware.nvidia.powerManagement) finegrained;
      nvidiaReprobe = pkgs.writeShellApplication {
        name = "nvidia-reprobe";
        text = ''
          shopt -s nullglob
          for dev in /sys/bus/pci/drivers/nvidia/????:??:??.?; do
            echo "''${dev##*/}" > /sys/bus/pci/drivers/nvidia/unbind
            echo "''${dev##*/}" > /sys/bus/pci/drivers/nvidia/bind
          done
        '';
      };
    in
    {
      imports = [
        self.modules.nixos.hardware-lenovo
        self.modules.nixos.hardware-x86-64-v3
        # Importuje też common-gpu-intel (sterowniki VA-API/OpenCL iGPU).
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.nixos-hardware.nixosModules.common-pc-laptop
        inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
      ];

      # Pakiety CUDA nie są w cache.nixos.org i kompilują się lokalnie — tylko
      # dla tej karty (Blackwell, sm_120) zamiast dla całej listy architektur.
      nixpkgs.config.cudaCapabilities = [ "12.0" ];

      # Włącza sterownik NVIDIA także bez serwera X (Wayland).
      services.xserver.videoDrivers = [ "nvidia" ];

      # Tymczasowe (temporary-fixes.md nr 1): reguły finegrained z nixpkgs
      # włączają runtime PM tylko na ACTION=="bind"; tu dGPU zostawało
      # z power/control = on (domyślne PCI), więc nigdy nie zasypiało (D3cold).
      # Jak 71-nvidia.rules z CachyOS: także przy coldplug ("add"), gdy
      # sterownik jest już zbindowany.
      services.udev.extraRules = lib.mkIf finegrained ''
        ACTION=="add|bind", SUBSYSTEM=="pci", DRIVERS=="nvidia", ATTR{vendor}=="0x10de", ATTR{class}=="0x03[0-9]*", TEST=="power/control", ATTR{power/control}="auto"
      '';

      # Tymczasowe (temporary-fixes.md nr 16): od Linuksa 7.3 kthready mają
      # korzeń w nullfs, a sterownik sonduje GPU przy ładowaniu modułu
      # w kthreadzie nv-probe, więc otwarcie /sys/bus/pci/devices/<bdf>/config
      # kończy się ENOENT i RTD3 wyłącza się po cichu (`Runtime D3 status: Not
      # supported`). Ponowne sondowanie przez unbind/bind biegnie w kontekście
      # procesu i plik się otwiera. W initrd, bo facter ładuje tam moduł nvidia
      # (hardware.facter.detected.boot.graphics.kernelModules), a GPU nikt
      # jeszcze nie używa: w stage 2 trzeba by najpierw wyładować nvidia_drm,
      # nvidia_modeset i nvidia_uvm, które trzyma KWin.
      boot.initrd.systemd = lib.mkIf finegrained {
        # make-initrd-ng kopiuje tylko podane ścieżki (z interpreterem
        # i bibliotekami), nie ścieżki z ExecStart jednostek.
        storePaths = [ nvidiaReprobe ];
        services.nvidia-reprobe = {
          description = "Re-probe NVIDIA GPUs from process context (runtime D3)";
          after = [ "systemd-modules-load.service" ];
          before = [ "initrd.target" ];
          wantedBy = [ "initrd.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe nvidiaReprobe;
          };
        };
      };

      assertions = [
        {
          assertion = !finegrained || lib.elem "nvidia" config.boot.initrd.kernelModules;
          message = "nvidia-reprobe (temporary-fixes.md nr 16) wymaga modułu nvidia w boot.initrd.kernelModules; bez niego RTD3 dGPU zostaje wyłączone.";
        }
      ];

      hardware = {
        facter.reportPath = ./facter.json;
        graphics = {
          enable = true;
          enable32Bit = true;
        };
        nvidia = {
          powerManagement.enable = true;
          powerManagement.finegrained = lib.mkDefault true;
          open = true;
          # Dynamic Boost (nvidia-powerd) przesuwa budżet mocy z CPU na GPU
          # w grach GPU-bound; bez demona GPU nie dostaje watów wliczonych
          # w maksymalne TGP (`nvidia-smi -q -d POWER` pod obciążeniem: Current
          # Power Limit ponad bazowe TGP). Nie blokuje D3cold (sprawdzone
          # 2026-09-29, także z monitorem na DisplayPort).
          dynamicBoost.enable = true;
          package = config.boot.kernelPackages.nvidiaPackages.latest;
          # Tryb offload i polecenie nvidia-offload włącza common-gpu-nvidia
          # (nixos-hardware).
          prime.intelBusId = "PCI:0:2:0";
          prime.nvidiaBusId = "PCI:1:0:0";
        };
      };
    };
}
