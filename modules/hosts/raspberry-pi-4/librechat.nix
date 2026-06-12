{ customTop, ... }:
{
  flake.modules.nixos.librechat =
    { config, ... }:
    {
      age.secrets.librechat-env = {
        file = customTop.secretsDir + "/librechat-env.age";
        owner = "librechat";
        group = "librechat";
        mode = "0400";
      };

      services.librechat = {
        enable = true;
        enableLocalDB = true;
        credentialsFile = config.age.secrets.librechat-env.path;
      };
    };
}
