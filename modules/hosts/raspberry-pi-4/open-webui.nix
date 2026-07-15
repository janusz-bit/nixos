{ customTop, ... }:
{
  flake.modules.nixos.open-webui =
    { config, pkgs, ... }:
    {
      age.secrets.open-webui-hermes-env = {
        file = customTop.secretsDir + "/hermes-env.age";
      };

      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        environment = {
          # Ensure env vars always override DB-stored PersistentConfig values
          ENABLE_PERSISTENT_CONFIG = "False";
          # OpenAI-compatible API → Hermes Agent (sole model source)
          ENABLE_OPENAI_API = "true";
          OPENAI_API_BASE_URL = "http://127.0.0.1:8642/v1";
          # Disable Ollama API so Open WebUI only uses Hermes
          ENABLE_OLLAMA_API = "false";
          # Require authentication (first registered user becomes admin)
          WEBUI_AUTH = "True";
          # Stateful Responses API (forwarding previous_response_id)
          ENABLE_RESPONSES_API_STATEFUL = "1";
          # Cookie settings: Cloudflare Tunnel terminates TLS, so the
          # browser sees HTTPS while the backend only sees HTTP on
          # 127.0.0.1. Without these, Starlette's SessionMiddleware
          # encodes sessions in standard base64 (+, /, =), which strict
          # browsers (Brave, Chrome strict) reject per RFC 6265 — the
          # session cookie is dropped and login silently fails.
          # SameSite=none requires Secure=true; both are satisfied here
          # because Cloudflare serves HTTPS to the client.
          # Refs: open-webui#26382, open-webui#15373
          WEBUI_SESSION_COOKIE_SECURE = "true";
          WEBUI_SESSION_COOKIE_SAME_SITE = "none";
          WEBUI_AUTH_COOKIE_SECURE = "true";
          WEBUI_AUTH_COOKIE_SAME_SITE = "none";
        };
        # Shared API key with Hermes Agent (API_SERVER_KEY=OPENAI_API_KEY)
        environmentFile = config.age.secrets.open-webui-hermes-env.path;
      };
    };
}
