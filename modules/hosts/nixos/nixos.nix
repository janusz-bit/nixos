{ self, ... }:
{
  flake.nixosModules.nixos =
    { ... }:
    {
      imports = [
        self.nixosModules."nixos/specific"
        self.nixosModules."nixos/configuration"
        self.nixosModules."nixos/hardware-configuration"
        self.nixosModules."nixos/packages"
        # self.nixosModules."nixos/openclaw"
        self.nixosModules."nixos/podman"
        self.nixosModules."disko"
        self.nixosModules."nixos/niri"
        self.nixosModules."nixos/ai"
        self.nixosModules."nixos/appimage-run"
      ];
    };
}
