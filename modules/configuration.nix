{ ... }:
{
  flake.nixosModules.configuration =
    { pkgs, ... }:
    {
      nixpkgs.config.allowUnfree = true;

      environment.systemPackages = with pkgs; [
        vscode.fhs
        micro
        zed-editor-fhs
        nil
        nixd
      ];

      environment.sessionVariables.NIXOS_OZONE_WL = "1";

      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
}
