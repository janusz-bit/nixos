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
      age.secrets.notes = {
        file = ../_secrets/notes.age;
        owner = "root";
        mode = "0440";
      };
      age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
      imports = [
        inputs.agenix.nixosModules.default
      ];
    };
}
