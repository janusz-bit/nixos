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
  flake.nixosModules.git-home =
    { config, ... }:
    {
      home-manager.users.${config.custom.defaultUser} = {
        programs = {
          gh.enable = true;
          git = {
            enable = true;
            settings = gitConfig;
          };
        };
      };
    };

  flake.nixosModules.git-configuration =
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

  flake.homeModules.git-configuration =
    { pkgs, ... }:
    {
      programs.git = {
        enable = true;
        extraConfig = gitConfig;
      };
      programs.gh.enable = true;
    };
}
