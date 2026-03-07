{ ... }:
{
  flake.nixosModules.configuration =
    { pkgs, ... }:
    let
      editor = "zeditor --wait";
    in
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
      environment.sessionVariables.VISUAL = editor;
      environment.sessionVariables.EDITOR = editor;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
    };
}
