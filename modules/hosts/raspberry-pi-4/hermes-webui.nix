{
  self,
  inputs,
  custom,
  ...
}:
{
  flake.nixosModules."raspberry-pi-4/hermes-webui" =
    { config, pkgs, lib, ... }:
    {
      # Agenix secret for env vars (HERMES_WEBUI_PASSWORD, HERMES_WEBUI_GATEWAY_API_KEY)
      age.secrets.hermes-webui-env = {
        file = custom.secretsDir + "/hermes-webui-env.age";
        owner = "root";
        group = "root";
        mode = "0400";
      };

      virtualisation.oci-containers.containers.hermes-webui = {
        autoStart = true;
        image = "ghcr.io/nesquena/hermes-webui:latest";
        ports = [ "127.0.0.1:8787:8787" ];
        volumes = [
          "hermes-webui-state:/home/hermeswebui/.hermes/webui"
          "${inputs.hermes-agent}:/home/hermeswebui/.hermes/hermes-agent:ro"
        ];
        environment = {
          HERMES_WEBUI_CHAT_BACKEND = "gateway";
          HERMES_WEBUI_GATEWAY_BASE_URL = "http://host.containers.internal:8642";
          HERMES_WEBUI_HOST = "0.0.0.0";
          HERMES_WEBUI_PORT = "8787";
          HERMES_WEBUI_STATE_DIR = "/home/hermeswebui/.hermes/webui";
          HERMES_WEBUI_DEFAULT_MODEL = "kimi-k2.6";
          HERMES_HOME = "/home/hermeswebui/.hermes";
        };
        environmentFiles = [ config.age.secrets.hermes-webui-env.path ];
        extraOptions = [
          "--pull=always"
        ];
      };

      virtualisation.containers.enable = true;
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
        defaultNetwork.settings.dns_enabled = true;
      };
    };
}
