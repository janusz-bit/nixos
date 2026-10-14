# Git na każdym hoście: tożsamość z customTop (commity z tego repo i agentów),
# gałąź domyślna main, skróty gh:/github: oraz GitHub CLI.
{ customTop, ... }:
{
  flake.modules.nixos.base-git =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        config = {
          user.name = customTop.repository.user;
          user.email = customTop.email.full;
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
      };
      environment.systemPackages = with pkgs; [
        gh
      ];
    };
}
