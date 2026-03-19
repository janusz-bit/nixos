{ self, ... }:
{
  flake.nixosModules.base-agenix =
    { config, ... }:
    {
      environment.sessionVariables.CACHIX_AUTH_TOKEN = config.age.secrets.secret1.path;

      imports = [ self.nixosModules.agenix ];
    };
}
