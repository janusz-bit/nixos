{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs2.url = "github:nixos/nixpkgs?ref=nixos-unstable/d8741a476715f20b54c2cf9f6da7ee4237a1be1f";
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
