{ self, ... }:
{
  flake.nixosModules."base/agenix" =
    { config, pkgs, ... }:
    {
      environment.sessionVariables.CACHIX_AUTH_TOKEN = "${pkgs.lib.getExe pkgs.cat} ${config.age.secrets.cachix-authtoken.path}";
      environment.sessionVariables.GITHUB_TOKEN = "${pkgs.lib.getExe pkgs.cat} ${config.age.secrets.github-token.path}";
      environment.sessionVariables.OLLAMA_API_KEY = "${pkgs.lib.getExe pkgs.cat} ${config.age.secrets.ollama-api-key.path}";

      imports = [ self.nixosModules."agenix" ];
    };
}
