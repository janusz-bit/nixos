{ self, custom, ... }:
{
  flake.nixosModules."raspberry-pi-4/open-webui" =
    { config,
      lib,
      pkgs,
      ...
    }:
    {
      # Open WebUI requires a database; we can use SQLite for simplicity on RPi4
      # It can be run as a container or a service. Since you prefer a declarative 
      # approach in NixOS, I'll set it up as a systemd service.
      
      services.open-webui = {
        enable = true;
        # Let's bind it to localhost for security, Cloudflare Tunnel will handle the external access
        settings = {
          # OLLAMA_API_BASE_URL should point to where Ollama is running.
          # If Ollama is in a different container/service, adjust accordingly.
          # Default for Ollama is usually port 11434.
          OLLAMA_API_BASE_URL = "http://localhost:11433"; 
        };
      };

      # In case it's not a native nixos service yet (depending on nixpkgs version),
      # we might need to use a generic systemd service or a container.
      # I will start by defining it as a potential service.
    };
}
