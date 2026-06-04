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
      cachix
      inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
      nix-update
      tlrc
      fzf
      hw-probe
      htop
      cloudflared
      gemini-cli
      vulnix
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
        mode: remote:
        let
          flakeRef = if remote then custom.repository.linkFlake else custom.repository.place;
        in
        "sudo nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${config.customBot.flakeTarget}${optionalStr remote " --refresh"}";
      optionalStr = cond: str: if cond then str else "";
    in
    {
      # Pushing
      push = "nix build ${custom.repository.linkFlake}#nixosConfigurations.${config.customBot.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | CACHIX_AUTH_TOKEN=$(cat ${config.age.secrets.cachix-authtoken.path}) cachix push ${custom.cache.cachix.name}";

      # Update systemu
      update = update_alias "switch" true;
      update-boot = update_alias "boot" true;
      update-local = update_alias "switch" false;
      update-local-boot = update_alias "boot" false;
    };

  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "${custom.cache.cachix.url}"
    ];
    extra-trusted-public-keys = [
      "${custom.cache.cachix.pubKey}"
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

      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 22 ];
        allowedUDPPorts = [ ];
      };

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
