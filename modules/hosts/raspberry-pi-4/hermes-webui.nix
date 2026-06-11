{ customTop, inputs, ... }:
{
  flake.modules.nixos.hermes-webui =
    { config, pkgs, ... }:
    {
      imports = [
        inputs.hermes-webui.nixosModules.default
      ];

      # Wczytujemy hermes-env.age jako sekret współdzielony z hermes-agent
      age.secrets.hermes-webui-env = {
        file = customTop.secretsDir + "/hermes-env.age";
        owner = "hermes";
        group = "hermes";
        mode = "0400";
      };

      services.hermes-workspace = {
        enable = true;
        package = inputs.hermes-webui.packages.${pkgs.system}.default;
        host = "127.0.0.1";
        port = 8787;
        hermesApiUrl = "http://127.0.0.1:8642";
        hermesDashboardUrl = "http://127.0.0.1:9119";
        user = "hermes";
        group = "hermes";
        # Keep using the same home directory for state
        dataDir = "/var/lib/hermes";
        environmentFile = config.age.secrets.hermes-webui-env.path;
      };
    };
}
