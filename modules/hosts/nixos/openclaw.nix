{ inputs, ... }:
{
  flake.nixosModules.nixos-openclaw =
    {
      config,
      ...
    }:

    {
      # Ten moduł zakłada, że virtualisation.podman jest włączony w db.nix lub innym module
      virtualisation.oci-containers = {
        backend = "podman";
        containers.openclaw = {
          image = "ghcr.io/openclaw/openclaw:latest";
          ports = [ "8080:8080" ];
          environment = {
            LLM_PROVIDER = "ollama";
            OLLAMA_URL = "http://172.17.0.1:11434";
            DEFAULT_MODEL = "gemma4:31b";
          };
          volumes = [ "/home/${config.custom.defaultUser}/.openclaw:/app/data" ];
        };
      };
    };
}
