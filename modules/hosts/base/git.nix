{ self, customTop, ... }:
let
  gitConfig = {
    user.name = "${customTop.repository.user}";
    user.email = "${customTop.email.full}";
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
  flake.nixosModules."base/git" =
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
