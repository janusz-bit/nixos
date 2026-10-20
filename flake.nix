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
    # Kernel CachyOS (zamiast chaotic). Gałąź release = wersje zbudowane przez
    # Hydrę autora; jego cache nie jest używany (kernel kompiluje się lokalnie
    # albo w CI cachyos-kernel-update) — modules/desktop/kernel.nix.
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
    # Własny nixpkgs celowo — pakiety llm-agents są budowane pod niego.
    # Cache.numtide.com nie jest już używany, więc nowe wersje kompilują się
    # lokalnie.
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Brulion — notatki w Markdownie (własna aplikacja, nie ma jej w nixpkgs);
    # flake daje pakiet i moduł programs.brulion (modules/desktop/brulion.nix).
    # follows: brak własnego cache, a ten sam nixpkgs = to samo Qt co w Plasmie
    # (wtyczki motywów Qt pasują).
    brulion = {
      url = "github:janusz-bit/brulion";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Paczki skilli agentów (modules/skills/external.nix): wejście, nie pakiet
    # lokalny, bo nazwy skilli czyta builtins.readDir przy ewaluacji, a na
    # wyniku fetchFromGitHub byłoby to IFD. Aktualizuje je `nix flake update`
    # w flake-update.
    qt-agent-skills = {
      url = "github:TheQtCompanyRnD/agent-skills";
      flake = false;
    };
    # Waywallen — dynamiczne tapety na Waylandzie (zamiennik Wallpaper Engine).
    # Dawniej flake nix-waywallen; teraz pakiet lokalny z oficjalnego AppImage
    # + prebuildu open-wallpaper-engine (modules/packages/_waywallen).
    # Plugin KDE Plasma: modules/packages/_waywallen-kde-plugin (release
    # v0.3.3 waywallen-display — naprawa "plasma empty displays on login").
  };

  # Jedyna lista cache flake'a: CI i pierwszy rebuild z --accept-flake-config
  # czytają ją stąd, a hosty dostają te same listy w nix.settings
  # (customTop.nixConfig, modules/args.nix). nixConfig inputów NIE jest
  # dziedziczony — cache inputów trzeba wymienić tutaj.
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
