{ self, customTop, ... }:
{
  flake.modules.nixos.gitea =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      services.gitea = {
        enable = true;
        database.type = "sqlite3";

        settings = {
          server = {
            DOMAIN = "git.${customTop.site.full}";
            ROOT_URL = "https://git.${customTop.site.full}/";
            HTTP_ADDR = "127.0.0.1";
            HTTP_PORT = 3000;
            DISABLE_SSH = true;
          };
          service.DISABLE_REGISTRATION = true;
          session.COOKIE_SECURE = true;
        };
      };
    };
}