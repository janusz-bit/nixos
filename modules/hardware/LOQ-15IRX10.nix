{ inputs, self, ... }:
{
  # Lenovo LOQ 15IRX10: i5-13450HX (Iris Xe) + RTX 5060 Laptop (PRIME offload).
  flake.modules.nixos.hardware-LOQ-15IRX10 =
    {
      config,
      lib,
      ...
    }:
    let
      nvidiaLatest = config.boot.kernelPackages.nvidiaPackages.latest;
    in
    {
      # Pakiety CUDA (ollama-cuda, OBS z cudaSupport) nie są w cache.nixos.org
      # i kompilują się lokalnie — tylko dla tej karty (Blackwell, sm_120)
      # zamiast dla całej listy architektur.
      nixpkgs.config.cudaCapabilities = [ "12.0" ];

      # Włącza sterownik NVIDIA także bez serwera X (Wayland).
      services.xserver.videoDrivers = [ "nvidia" ];

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
          # See temporary-fixes.md: CachyOS still patches a const GPIO argument,
          # but NVIDIA 615.71.09 already ships the corrected signature.
          package = nvidiaLatest // {
            open = nvidiaLatest.open.overrideAttrs (old: {
              postPatch = lib.replaceString "--replace-fail" "--replace-warn" (old.postPatch or "");
            });
          };
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
        self.modules.nixos.build-flags-x86-64-v3
        inputs.nixos-hardware.nixosModules.common-cpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-intel
        inputs.nixos-hardware.nixosModules.common-gpu-nvidia
        inputs.nixos-hardware.nixosModules.common-pc-laptop
        inputs.nixos-hardware.nixosModules.common-pc-laptop-ssd
      ];
    };

}
