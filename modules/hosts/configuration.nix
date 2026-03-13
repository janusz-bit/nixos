{ inputs, self, ... }:
let
  editor = "micro";

  sharedPackages =
    pkgs: with pkgs; [
      micro
      nil
      nixd
      # inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default
      fresh-editor
      # self.packages.${pkgs.stdenv.hostPlatform.system}.my-neovim
    ];

  sharedSessionVariables = {
    NIXOS_OZONE_WL = "1";
    VISUAL = editor;
    EDITOR = editor;
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
