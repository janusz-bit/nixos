{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs1.url = "github:nixos/nixpkgs/9807714d6944a957c2e036f84b0ff8caf9930bc0";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    g14_patches = {
      url = "github:CachyOS/kernel-patches";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs1,
      nixos-hardware,
      ...
    }@inputs:
    {

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          nixos-hardware.nixosModules.asus-fa507nv
        ];
      };

    };
}
