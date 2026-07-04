{ self, config, ... }:
{
  flake.modules.nixos.base-agenix =
    { config, pkgs, ... }:
    {
      environment.shellInit = ''
        export CACHIX_AUTH_TOKEN=$(cat ${config.age.secrets.cachix-authtoken.path})
        export GITHUB_TOKEN=$(cat ${config.age.secrets.github-token.path})
        export OLLAMA_API_KEY=$(cat ${config.age.secrets.ollama-api-key.path})
        export GOOGLE_API_KEY=$(cat ${config.age.secrets.google-api-key.path})
        export NIX_CONFIG="access-tokens = github.com=$(cat ${config.age.secrets.github-token.path})"
      '';

      imports = [ self.modules.nixos.agenix ];
    };
}
