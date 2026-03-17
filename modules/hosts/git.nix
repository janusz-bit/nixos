{ self, ... }:
let
  config = {
    user.name = "janusz-bit";
    user.email = "janusz-bit@proton.me";
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
  flake.nixosModules.git-home = _: {
    home-manager.users.nixos = {
      programs = {
        gh.enable = true;
        git = {
          enable = true;
          settings = config;
        };
      };
    };
  };

  flake.nixosModules.git-configuration =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        inherit config;
      };
      environment.systemPackages = with pkgs; [
        gh
      ];
    };

  flake.homeModules.git-configuration =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        extraConfig = config;
      };
      programs.gh.enable = true;
    };
}
