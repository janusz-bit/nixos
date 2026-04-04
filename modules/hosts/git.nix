{ self, custom, ... }:
let
  config = {
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
