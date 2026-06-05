{ self, ... }:
let
  gitConfig = config: {
    user.name = config.customTop.repository.user;
    user.email = config.customTop.email.full;
    init.defaultBranch = "main";
    url = {
      "https://github.com/" = {
        insteadOf = [
          "gh:"
          "github:"
        ];
      };
    };
  };
in
{
  flake.modules.nixos.base-git =
    { config, pkgs, ... }:
    {
      programs.git = {
        enable = true;
        config = gitConfig config;
      };
      environment.systemPackages = with pkgs; [
        gh
      ];
    };

}
