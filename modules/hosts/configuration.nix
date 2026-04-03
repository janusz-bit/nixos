{ inputs, self, ... }:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro
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
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
  };

  environmentShellAliases = config: rec {
    push = "export CACHIX_AUTH_TOKEN=$(sudo cat ${config.age.secrets.secret1.path})\nnix build github:janusz-bit/nixos#nixosConfigurations.${config.custom.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | cachix push janusz-bit";
    update = "sudo nixos-rebuild switch --sudo --flake github:janusz-bit/nixos#${config.custom.flakeTarget} --refresh";
  };

  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];

  };
in
{
  flake.nixosModules.configuration =
    { pkgs, config, ... }:

    {
      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = sharedPackages pkgs;
      environment.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
      environment.shellAliases = environmentShellAliases config;

      # Setting environment.localBinInPath = true; is highly recommended, because uv will install binaries in ~/.local/bin.
      environment.localBinInPath = true;
      # Fix uv
      programs.nix-ld.enable = true;

      programs.nix-index-database.comma.enable = true;
    };

  flake.homeModules.configuration =
    { pkgs, config, ... }:

    {
      nixpkgs.config.allowUnfree = true;

      home.packages = sharedPackages pkgs;
      home.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
      environment.shellAliases = environmentShellAliases config;
    };
}
