{
  inputs,
  self,
  custom,
  ...
}:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro-full
      nil
      nixd
      #       inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default
      # fresh-editor
      # self.packages.${pkgs.stdenv.hostPlatform.system}.my-neovim
      nixfmt-tree
      uv
      toybox
      statix
      kdePackages.kleopatra
      attic-client
      cachix
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
      nix-update
      tlrc
      fzf
      hw-probe
      htop
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
  };

  environmentShellAliases =
    config: pkgs:
    let
      update_alias =
        mode:
        "sudo nixos-rebuild ${mode} --sudo --flake ${custom.repository.linkFlake}#${config.custom.flakeTarget} --refresh";

      push_cmd =
        serverName:
        "nix build ${custom.repository.linkFlake}#nixosConfigurations.${config.custom.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | attic push ${serverName}:nixos-builds --stdin";

      # Narzędzie wyciągające token, by nie duplikować logiki
      getToken = "$(${pkgs.gawk}/bin/awk -F'\\\"' '/token/ {print $2; exit}' ~/.config/attic/config.toml)";
    in
    {
      # Pushing
      push = push_cmd "global-cache";
      push-local = push_cmd "local-cache";

      # Logowanie (konfiguracja klienta - wymagane tylko raz)
      attic-login = "attic login global-cache https://cache.${custom.site.full}/ ${getToken}";
      attic-login-local = "attic login local-cache http://${custom.site.atticIp}:8080/ ${getToken}";

      # Update systemu
      update = update_alias "switch";
      update-boot = update_alias "boot";
    };

  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "http://${custom.site.atticIp}:8080/nixos-builds"
      "https://cache.${custom.site.full}/nixos-builds"
    ];
    extra-trusted-public-keys = [
      "nixos-builds:FdfmW2lSPWomDoWn5dNZv5ZJa+i5nL8niWqk/RKVWRc="
    ];
  };
in
{
  flake.nixosModules."base/configuration" =
    {
      pkgs,
      config,
      ...
    }:

    {

      imports = [ inputs.nix-index-database.nixosModules.default ];
      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = sharedPackages pkgs;
      environment.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
      environment.shellAliases = environmentShellAliases config pkgs;

      # Setting environment.localBinInPath = true; is highly recommended, because uv will install binaries in ~/.local/bin.
      environment.localBinInPath = true;
      # Fix uv
      programs.nix-ld.enable = true;

      programs.nix-index-database.comma.enable = true;

      programs.direnv.enable = true;
    };

  flake.homeModules.configuration =
    {
      pkgs,
      config,
      ...
    }:

    {
      nixpkgs.config.allowUnfree = true;

      home.packages = sharedPackages pkgs;
      home.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
      home.shellAliases = environmentShellAliases config pkgs;
    };
}
