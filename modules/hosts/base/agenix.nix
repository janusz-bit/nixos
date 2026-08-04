{ self, ... }:
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
        export OPENCODE_GO_API_KEY=$(cat ${config.age.secrets.opencode.path})
        # Plik env w formacie KLUCZ=wartość (bez `export`) — ten sam plik jest
        # używany jako systemd EnvironmentFile, które nie rozumie składni `export`.
        # `set -a` eksportuje wszystkie zmienne z sourcowanego pliku do procesów potomnych.
        set -a
        source "${config.age.secrets.llmgateway-api-key-shared.path}"
        set +a
      '';

      imports = [ self.modules.nixos.agenix ];
    };
}
