{ inputs, custom, ... }:
{
  flake.nixosModules."agenix" =
    { config, ... }:
    {
      age.secrets.secret1 = {
        file = custom.secretsDir + "/secret1.age";
        owner = "root";
        mode = "0440";
      };
      age.secrets.github-token = {
        file = custom.secretsDir + "/GITHUB_TOKEN.age";
        owner = "root";
        mode = "0440";
      };
      age.secrets.cachix-authtoken = {
        file = custom.secretsDir + "/cachix-authtoken-token.age";
        owner = "root";
        mode = "0440";
      };
      age.secrets.notes = {
        file = custom.secretsDir + "/notes.age";
        owner = "root";
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
