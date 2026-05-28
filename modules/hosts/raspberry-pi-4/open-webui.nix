{ ... }:
{
  flake.nixosModules."raspberry-pi-4/open-webui" =
    { config, pkgs, ... }:
    {
      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        environment = {
          # Point to Hermes Agent API Server (OpenAI-compatible)
          OPENAI_API_BASE_URL = "http://127.0.0.1:8642/v1";
          # Disable Ollama so it doesn't shadow the model picker
          ENABLE_OLLAMA_API = "true";
          # Require authentication (first registered user becomes admin)
          WEBUI_AUTH = "True";
        };
        # Shared API key with Hermes Agent (API_SERVER_KEY=OPENAI_API_KEY)
        environmentFile = config.age.secrets.hermes-api-key.path;
      };
    };
}
