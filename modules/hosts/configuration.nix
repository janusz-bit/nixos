{ inputs, self, ... }:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro
      nil
      nixd
      # inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default
      # fresh-editor
      # self.packages.${pkgs.stdenv.hostPlatform.system}.my-neovim
      nixfmt-tree
      uv
      toybox
      statix
      kdePackages.kleopatra
      cachix
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
  };

  environment.shellAliases = {
    cachix-system = ''
      nix build github:janusz-bit/nixos#nixosConfigurations.nixos.config.system.build.toplevel --no-link --print-out-paths | cachix push janusz-bit
    '';
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
    { pkgs, ... }:

    {
      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = sharedPackages pkgs;
      environment.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
      environment.shellAliases = environment.shellAliases;

      # Setting environment.localBinInPath = true; is highly recommended, because uv will install binaries in ~/.local/bin.
      environment.localBinInPath = true;
      # Fix uv
      programs.nix-ld.enable = true;

      programs.nix-index-database.comma.enable = true;
    };

  flake.homeModules.configuration =
    { pkgs, ... }:

    {
      nixpkgs.config.allowUnfree = true;

      home.packages = sharedPackages pkgs;
      home.sessionVariables = sharedSessionVariables;
      nix.settings = sharedNixSettings;
    };
}
