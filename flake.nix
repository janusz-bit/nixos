# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    # Kernel CachyOS (zamiast chaotic). Gałąź release = kernele zbudowane przez
    # Hydrę autora i obecne w jego cache (attic.xuyh0120.win/lantian, patrz
    # nixConfig niżej). Cache trafia tylko przy overlays.pinned (ten sam nixpkgs
    # co w Hydrze) — modules/hosts/nixos/configuration.nix.
    # NIE ustawiać inputs.nixpkgs.follows - musi mieć swój nixpkgs dla zgodności patchy!
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
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
    github-actions-nix = {
      url = "github:synapdeck/github-actions-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Tracks upstream (unpinned). The previous pin to 3f2a389c... existed
    # because topup.ts introduced a broken @hermes/shared/charge-settlement
    # import in nix/tui.nix; upstream moved on and the pin was lifted.
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # Własny nixpkgs celowo — pakiety są w cache.numtide.com tylko dla niego.
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Helium Browser (fork ungoogled-chromium) — oficjalne binaria (tar.xz)
    # spakowane przez flake'a; wersję i hashe bumpuje u nich GitHub Action,
    # u nas `nix flake update`. Użycie: modules/hosts/nixos/helium.nix.
    helium-browser = {
      url = "github:ominit/helium-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };
    # Waywallen — dynamiczne tapety na Waylandzie (zamiennik Wallpaper Engine).
    # Dawniej flake nix-waywallen; teraz pakiet lokalny z oficjalnego AppImage
    # + prebuildu open-wallpaper-engine (modules/packages/_waywallen).
    # Plugin KDE Plasma: modules/packages/_waywallen-kde-plugin (release
    # v0.3.3 waywallen-display — naprawa "plasma empty displays on login").
  };

  # nixConfig inputów NIE jest dziedziczony — cache inputów trzeba wymienić
  # tutaj (CI, pierwszy rebuild z --accept-flake-config) i w nix.settings
  # (modules/hosts/base/configuration.nix, źródło: customTop.cache).
  nixConfig = {
    extra-substituters = [
      "https://janusz-bit.cachix.org"
      "https://attic.xuyh0120.win/lantian"
      "https://cache.numtide.com"
    ];
    extra-trusted-public-keys = [
      "janusz-bit.cachix.org-1:4stTiufAF02BAXw8HNvYslAmUlPbZPIRhIGht0gSMoo="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
    ];
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake { inherit inputs; } (inputs.import-tree ./modules);
}
