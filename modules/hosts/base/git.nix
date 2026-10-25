# Git na każdym hoście: tożsamość z customTop (commity z tego repo i agentów),
# gałąź domyślna main, skróty gh:/github: oraz GitHub CLI.
_: {
  flake.modules.nixos.base-git =
    { config, pkgs, ... }:
    {
      programs.git = {
        enable = true;
        config = {
          user.name = config.customTop.owner;
          user.email = config.customTop.email;
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
