{ inputs, customTop, ... }:
{
  flake.nixosModules."agenix" =
    { config, ... }:
    {
      age.secrets.ollama-api-key = {
        file = customTop.secretsDir + "/ollama-api-key.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.secret1 = {
        file = customTop.secretsDir + "/secret1.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.github-token = {
        file = customTop.secretsDir + "/GITHUB_TOKEN.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.cachix-authtoken = {
        file = customTop.secretsDir + "/cachix-authtoken-token.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.notes = {
        file = customTop.secretsDir + "/notes.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.google-api-key = {
        file = customTop.secretsDir + "/google-api-key.age";
        owner = "root";
        group = "users";
        mode = "0440";
      };
      age.secrets.hermes-api-key = {
        file = customTop.secretsDir + "/hermes-api-key.age";
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
