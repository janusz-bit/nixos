{ self, ... }:
{
  flake.nixosModules.base-agenix =
    { config, ... }:
    {
      environment.sessionVariables.CACHIX_AUTH_TOKEN = config.age.secrets.secret1.path;
      environment.sessionVariables.GITHUB_TOKEN = config.age.secrets.github-token.path;

      imports = [ self.nixosModules.agenix ];
    };
}
