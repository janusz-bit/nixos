{ self, ... }:
{
  flake.nixosModules."base/agenix" =
    { config, pkgs, ... }:
    {
      environment.shellInit = ''
        export CACHIX_AUTH_TOKEN=$(cat ${config.age.secrets.cachix-authtoken.path})
        export GITHUB_TOKEN=$(cat ${config.age.secrets.github-token.path})
        export OLLAMA_API_KEY=$(cat ${config.age.secrets.ollama-api-key.path})
      '';

      imports = [ self.nixosModules."agenix" ];
    };
}
