{ inputs, ... }:
{
  flake.nixosModules.agenix =
    { config, ... }:
    {
      age.secrets.secret1 = {
        file = ../_secrets/secret1.age;
        owner = "root";
        mode = "0440";
      };
      age.secrets.github-token = {
        file = ../_secrets/GITHUB_TOKEN.age;
        owner = "root";
        mode = "0440";
      };
      age.secrets.notes = {
        file = ../_secrets/notes.age;
        owner = "root";
        mode = "0440";
      };
      age.identityPaths = [
        "/etc/ssh/ssh_host_ed25519_key"
        "/home/dinosaur/.ssh/id_ed25519"
        "/home/wsl/.ssh/id_ed25519"
        "/root/.ssh/id_ed25519"
      ];
      imports = [
        inputs.agenix.nixosModules.default
      ];
    };
}
