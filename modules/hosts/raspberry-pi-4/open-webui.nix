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
        # Internal port — nginx reverse proxy listens on 8080 (cloudflared ingress target)
        port = 3001;
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

      # ─────────────────────────────────────────────────────────────
      # nginx reverse proxy with static asset caching
      #
      # Problem: open-webui (SvelteKit SPA) serves ~52 JS chunks, CSS,
      # and fonts without Cache-Control headers. Cloudflare sees no
      # cache directives → cf-cache-status: DYNAMIC on everything. After
      # login, crossorigin="use-credentials" + cookies make Cloudflare
      # treat every request as uncacheable. Each page reload = 52+
      # round-trips through the QUIC tunnel to the RPi4, which has one
      # uvicorn worker and ~100 MB free RAM → page hangs.
      #
      # Solution: nginx sits between cloudflared and open-webui,
      # caches immutable static assets locally, adds Cache-Control
      # headers so Cloudflare can cache them too, compresses responses
      # with gzip, and buffers slow backend responses.
      # ─────────────────────────────────────────────────────────────

      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedGzipSettings = true;

        # proxy_cache_path must go in the http{} block
        appendHttpConfig = ''
          proxy_cache_path /var/cache/nginx/open-webui
            levels=1:2
            keys_zone=open-webui-cache:10m
            max_size=100m
            inactive=7d
            use_temp_path=off;
        '';

        virtualHosts."chat.${customTop.site.full}" = {
          # Listen on 8080 — cloudflared ingress target (unchanged)
          listen = [
            { addr = "127.0.0.1"; port = 8080; }
          ];

          locations = {
            # ── Static assets: cache aggressively ──
            # SvelteKit immutable chunks (hashed filenames, never change)
            "/_app/immutable/" = {
              proxyPass = "http://127.0.0.1:3001";
              extraConfig = ''
                # Cache in nginx for 7d, serve stale if backend is slow
                proxy_cache open-webui-cache;
                proxy_cache_valid 200 7d;
                proxy_cache_use_stale error timeout updating;
                proxy_cache_lock on;

                # Add Cache-Control so Cloudflare caches these too
                # immutable = browser never revalidates
                add_header Cache-Control "public, max-age=604800, immutable" always;
                # Strip cookies from static requests → Cloudflare can cache
                proxy_hide_header Set-Cookie;
                proxy_pass_header Cache-Control;

                # Don't pass cookies to backend for static files
                proxy_set_header Cookie "";
              '';
            };

            # Static files (favicon, manifest, etc.)
            "/static/" = {
              proxyPass = "http://127.0.0.1:3001";
              extraConfig = ''
                proxy_cache open-webui-cache;
                proxy_cache_valid 200 7d;
                proxy_cache_use_stale error timeout updating;
                proxy_cache_lock on;

                add_header Cache-Control "public, max-age=604800, immutable" always;
                proxy_hide_header Set-Cookie;
                proxy_set_header Cookie "";
              '';
            };

            # ── API + WebSocket + everything else: no cache, proxy as-is ──
            "/" = {
              proxyPass = "http://127.0.0.1:3001";
              proxyWebsockets = true;
              extraConfig = ''
                # Don't cache dynamic content
                proxy_cache off;
                # Buffer responses so slow backend doesn't hold client connection
                proxy_buffering on;
                proxy_buffer_size 16k;
                proxy_buffers 8 32k;
                # Timeouts for long-running API calls (streaming, etc.)
                proxy_read_timeout 300s;
                proxy_send_timeout 300s;
              '';
            };
          };
        };
      };

      # Ensure nginx cache directory exists with correct ownership
      systemd.tmpfiles.rules = [
        "d /var/cache/nginx/open-webui 0750 nginx nginx - -"
      ];
    };
}