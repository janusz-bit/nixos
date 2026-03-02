{ self, ... }:
{
  flake.nixosModules.git-home =
    { ... }:
    {
      home-manager.users.nixos = {
        programs = {
          gh.enable = true;
          git = {
            enable = true;
            settings = {
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
          };
        };
      };
    };

  # flake.nixosModules.git-configuration =
  #   { ... }:
  #   {
  #     programs.git = {
  #       enable = true;
  #       config = (self.nixosModules.git-home { }).nixos.programs.git.settings;
  #     };
  #   };
}
