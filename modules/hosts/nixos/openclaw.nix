{ inputs, ... }:
{
  flake.nixosModules."nixos/openclaw" =
    {
      config,
      ...
    }:

    {
      virtualisation.oci-containers = {
        backend = "podman";
        containers.openclaw = {
          image = "ghcr.io/openclaw/openclaw:latest";
          autoStart = true;
          ports = [ "127.0.0.1:18789:18789" ];
          environment = {
            LLM_PROVIDER = "ollama";
            OLLAMA_URL = "http://10.88.0.1:11434";
            DEFAULT_MODEL = "gemma4:31b";
          };
          volumes = [ "/home/${config.custom.defaultUser}/.openclaw:/app/data" ];
        };
      };
    };
}
