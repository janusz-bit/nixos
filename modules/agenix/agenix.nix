{ inputs, customTop, ... }:
{
  flake.modules.nixos.agenix =
    { ... }:
    {
      age = {
        secrets = {
          ollama-api-key = {
            file = customTop.secretsDir + "/ollama-api-key.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          secret1 = {
            file = customTop.secretsDir + "/secret1.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          github-token = {
            file = customTop.secretsDir + "/GITHUB_TOKEN.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          cachix-authtoken = {
            file = customTop.secretsDir + "/cachix-authtoken-token.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          notes = {
            file = customTop.secretsDir + "/notes.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          google-api-key = {
            file = customTop.secretsDir + "/google-api-key.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          hermes-api-key = {
            file = customTop.secretsDir + "/hermes-api-key.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          opencode = {
            file = customTop.secretsDir + "/opencode.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
          llmgateway-api-key-shared = {
            file = customTop.secretsDir + "/llmgateway-api-key.age";
            owner = "root";
            group = "users";
            mode = "0440";
          };
        };
        identityPaths = [
          "/root/.ssh/id_ed25519"
        ];
      };
      imports = [
        inputs.agenix.nixosModules.default
      ];
    };
}
