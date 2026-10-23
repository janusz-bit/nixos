{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    # Kanał nixos-unstable-small z własnym nixpkgs; obecnie tylko PHP Nextclouda
    # na RPi (PHP2Shell, rpi-nextcloud): nixos-unstable nie ma jeszcze PHP 8.4.27,
    # a przestawienie głównego nixpkgs przebudowałoby wszystkie hosty.
    # Tymczasowe: temporary-fixes.md.
    nixpkgs-unstable-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    import-tree.url = "github:vic/import-tree";
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    nixos-wsl.inputs.nixpkgs.follows = "nixpkgs";
    nix-index-database.url = "github:nix-community/nix-index-database";
    nix-index-database.inputs.nixpkgs.follows = "nixpkgs";
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
    # Kernel CachyOS (desktop/kernel.nix); gałąź release = wersje zbudowane
    # przez Hydrę autora, którego cache nie jest używany. NIE ustawiać follows:
    # patche kernela są pod własny nixpkgs tego wejścia.
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    agenix.url = "github:ryantm/agenix";
    agenix.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks-nix.url = "github:cachix/git-hooks.nix";
    git-hooks-nix.inputs.nixpkgs.follows = "nixpkgs";
    github-actions-nix.url = "github:synapdeck/github-actions-nix";
    github-actions-nix.inputs.nixpkgs.follows = "nixpkgs";
    hermes-agent.url = "github:NousResearch/hermes-agent";
    # Bez follows: pakiety llm-agents są budowane pod własny nixpkgs (cache
    # numtide nie jest używany, więc kompilują się lokalnie).
    llm-agents.url = "github:numtide/llm-agents.nix";
    # Brulion (własna aplikacja, desktop/brulion.nix), gałąź release: stabilne
    # wydania zamiast rozwoju. follows: brak własnego cache, a to samo Qt co
    # Plasma (wtyczki motywów pasują).
    brulion.url = "github:janusz-bit/brulion?ref=release";
    brulion.inputs.nixpkgs.follows = "nixpkgs";
    # Wejście, nie pakiet lokalny: skills/external.nix czyta nazwy skilli przez
    # builtins.readDir przy ewaluacji, na wyniku fetchera byłoby to IFD.
    qt-agent-skills.url = "github:TheQtCompanyRnD/agent-skills";
    qt-agent-skills.flake = false;
  };

  # Jedyna lista cache: hosty (customTop.nixConfig), CI i pierwszy rebuild
  # z --accept-flake-config. nixConfig inputów nie jest dziedziczony — ich
  # cache trzeba dopisać tutaj.
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
