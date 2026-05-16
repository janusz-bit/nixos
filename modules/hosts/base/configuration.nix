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
    in
    {
      # Pushing
      push = "nix build ${custom.repository.linkFlake}#nixosConfigurations.${config.custom.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | CACHIX_AUTH_TOKEN=$(cat ${config.age.secrets.cachix-authtoken.path}) cachix push ${custom.cache.cachix.name}";

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
