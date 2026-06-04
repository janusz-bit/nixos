{ self, custom, ... }:
let
  gitConfig = {
    user.name = "${custom.repository.user}";
    user.email = "${custom.email.full}";
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
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        config = gitConfig;
      };
      environment.systemPackages = with pkgs; [
        gh
      ];
    };

}
