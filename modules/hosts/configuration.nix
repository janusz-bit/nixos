{ inputs, self, ... }:
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
        # inputs.fresh.packages.${pkgs.stdenv.hostPlatform.system}.default
        fresh-editor
        # self.packages.${pkgs.stdenv.hostPlatform.system}.my-neovim
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
