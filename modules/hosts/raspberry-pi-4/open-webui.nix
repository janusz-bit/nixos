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
          # Ensure env vars always override DB-stored PersistentConfig values
          ENABLE_PERSISTENT_CONFIG = "False";
          # OpenAI-compatible API → Hermes Agent
          ENABLE_OPENAI_API = "true";
          OPENAI_API_BASE_URL = "http://127.0.0.1:8642/v1";
          # Ollama local backend
          ENABLE_OLLAMA_API = "true";
          OLLAMA_BASE_URL = "http://127.0.0.1:11434";
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434/api";
          # Require authentication (first registered user becomes admin)
          WEBUI_AUTH = "True";
        };
        # Shared API key with Hermes Agent (API_SERVER_KEY=OPENAI_API_KEY)
        environmentFile = config.age.secrets.hermes-env.path;
      };
    };
}
