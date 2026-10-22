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
          user.name = customTop.owner;
          user.email = customTop.email;
          init.defaultBranch = "main";
          url."https://github.com/".insteadOf = [
            "gh:"
            "github:"
          ];
        };
      };
      environment.systemPackages = [ pkgs.gh ];
    };
}
