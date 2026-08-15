{
  inputs,
  self,
  customTop,
  ...
}:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro-full
      nil
      nixd
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
      vulnix
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
  };

  environmentShellAliases =
    config:
    let
      update_alias =
        mode: remote:
        let
          flakeRef = if remote then customTop.repository.linkFlake else customTop.repository.place;
        in
        "sudo nixos-rebuild ${mode} --sudo --flake ${flakeRef}#${config.customBot.flakeTarget}${optionalStr remote " --refresh"}";
      optionalStr = cond: str: if cond then str else "";
    in
    {
      # Pushing
      push = "nix build ${customTop.repository.linkFlake}#nixosConfigurations.${config.customBot.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | CACHIX_AUTH_TOKEN=$(cat ${config.age.secrets.cachix-authtoken.path}) cachix push ${customTop.cache.cachix.name}";

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
      "${customTop.cache.cachix.url}"
    ];
    extra-trusted-public-keys = [
      "${customTop.cache.cachix.pubKey}"
    ];
  };
in
{
  flake.modules.nixos.base-configuration =
    {
      pkgs,
      config,
      ...
    }:

    {

      imports = [ inputs.nix-index-database.nixosModules.default ];

      nixpkgs = {
        config.allowUnfree = true;
        overlays = [ self.overlays.opencode-config ];
      };

      networking = {
        nameservers = [
          "9.9.9.9"
          "149.112.112.112"
          "2620:fe::fe"
          "2620:fe::9"
        ];

        firewall = {
          enable = true;
          allowedTCPPorts = [ 22 ];
          allowedUDPPorts = [ ];
        };
      };

      environment = {
        systemPackages = sharedPackages pkgs;
        sessionVariables = sharedSessionVariables;
        shellAliases = environmentShellAliases config;

        # Setting environment.localBinInPath = true; is highly recommended, because uv will install binaries in ~/.local/bin.
        localBinInPath = true;
      };

      nix.settings = sharedNixSettings;

      programs = {
        # Fix uv
        nix-ld.enable = true;

        nix-index-database.comma.enable = true;

        direnv.enable = true;
      };

      # The ZFS module is pulled in by default by nixpkgs even when ZFS
      # is not in use. Explicitly disable forceImportRoot to silence the
      # 26.11 evaluation warning and reduce the risk of data loss.
      boot.zfs.forceImportRoot = false;
    };

  flake.homeModules.configuration =
    {
      pkgs,
      config,
      ...
    }:

    {
      nixpkgs.config.allowUnfree = true;

      home = {
        packages = sharedPackages pkgs;
        sessionVariables = sharedSessionVariables;
        shellAliases = environmentShellAliases config;
      };
      nix.settings = sharedNixSettings;
    };
}
