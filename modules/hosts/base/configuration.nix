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
    in
    {
      push = "nix build ${custom.repository.linkFlake}#nixosConfigurations.${config.custom.flakeTarget}.config.system.build.toplevel --refresh --no-link --print-out-paths | xargs nix path-info --json -r | ${pkgs.jq}/bin/jq -r 'to_entries[] | select(.value.signatures == null or all(.value.signatures[]; contains(\"cache.nixos.org\") | not)) | .key' | xargs -r attic push nixos-builds --no-closure";
      update = update_alias "switch";
      update-boot = update_alias "boot";
    };

  sharedNixSettings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    extra-substituters = [
      "https://cache.janusz-bit.com/nixos-builds"
    ];
    extra-trusted-public-keys = [
      "nixos-builds:g7DtqKioAfGeX76wt4lF9gzrpCj1ZCs8HGThHGwL5iA="
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
