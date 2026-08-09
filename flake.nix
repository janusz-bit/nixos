# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-26.05";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nvf.url = "github:notashelf/nvf";
    avf.url = "github:nix-community/nixos-avf";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    trilium = {
      url = "github:TriliumNext/Trilium/744646d07bff459d1db305b1c0a8ea0c99b9c27c";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    github-actions-nix.url = "github:synapdeck/github-actions-nix";
    # Tracks upstream (unpinned). The previous pin to 3f2a389c... existed
    # because topup.ts introduced a broken @hermes/shared/charge-settlement
    # import in nix/tui.nix; upstream moved on and the pin was lifted.
    hermes-agent.url = "github:NousResearch/hermes-agent";
  };

  nixConfig = {
    extra-substituters = [
      "https://janusz-bit.cachix.org"
    ];
    extra-trusted-public-keys = [
      "janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo="
    ];
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
