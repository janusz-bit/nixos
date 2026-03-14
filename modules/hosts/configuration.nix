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
      nixfmt-tree
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
    substituters = [ "https://attic.xuyh0120.win/lantian" ];
    trusted-public-keys = [ "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc=" ];
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
