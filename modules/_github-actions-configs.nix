{
  nixos = {
    arch = "x86_64-linux";
    kernelTarget = "nixosConfigurations.nixos.config.boot.kernelPackages.kernel";
  };
  raspberry-pi-4 = {
    arch = "aarch64-linux";
    kernelTarget = "nixosConfigurations.raspberry-pi-4.config.boot.kernelPackages.kernel";
  };
  raspberry-pi-4-sd-image = {
    arch = "aarch64-linux";
    buildTarget = "packages.aarch64-linux.raspberry-pi-4-sd-image";
  };
  wsl = {
    arch = "x86_64-linux";
  };
  droid = {
    arch = "aarch64-linux";
  };
}
