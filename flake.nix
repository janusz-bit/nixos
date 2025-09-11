{
  description = "A very basic flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nix-alien.url = "github:thiagokokada/nix-alien";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      nixos-hardware,
      chaotic,
      nixos-generators,
      ...
    }@inputs:
    {

      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          chaotic.nixosModules.default # IMPORTANT
          nixos-hardware.nixosModules.asus-fa507nv
        ];
      };

      packages.x86_64-linux = {
        customISO = nixos-generators.nixosGenerate {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };

          modules = [
            (
              { pkgs, modulesPath, lib, ... }:
              {
                imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-graphical-calamares-plasma6.nix") ];
                isoImage.squashfsCompression = "gzip -Xcompression-level 1";
                services.displayManager.autoLogin.user = lib.mkForce "nixos";
              }
            )
            # you can include your own nixos configuration here, i.e.
            # ./configuration.nix

            ./configuration.nix
            chaotic.nixosModules.default # IMPORTANT
            nixos-hardware.nixosModules.asus-fa507nv
          ];
          format = "install-iso";

          # optional arguments:
          # explicit nixpkgs and lib:
          # pkgs = nixpkgs.legacyPackages.x86_64-linux;
          # lib = nixpkgs.legacyPackages.x86_64-linux.lib;
          # additional arguments to pass to modules:
          # specialArgs = { myExtraArg = "foobar"; };

          # you can also define your own custom formats
          # customFormats = { "myFormat" = <myFormatModule>; ... };
          # format = "myFormat";
        };
      };

    };
}
