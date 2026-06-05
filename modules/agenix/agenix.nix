{ inputs, ... }:
{
  flake.modules.nixos.agenix =
    { config, ... }:
    {
      age.secrets.ollama-api-key = {
        file = config.customTop.secretsDir + "/ollama-api-key.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.secret1 = {
        file = config.customTop.secretsDir + "/secret1.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.github-token = {
        file = config.customTop.secretsDir + "/GITHUB_TOKEN.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.cachix-authtoken = {
        file = config.customTop.secretsDir + "/cachix-authtoken-token.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.notes = {
        file = config.customTop.secretsDir + "/notes.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.google-api-key = {
        file = config.customTop.secretsDir + "/google-api-key.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.hermes-api-key = {
        file = config.customTop.secretsDir + "/hermes-api-key.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.identityPaths = [
        "/root/.ssh/id_ed25519"
      ];
      imports = [
        inputs.agenix.nixosModules.default
      ];
    };
}
