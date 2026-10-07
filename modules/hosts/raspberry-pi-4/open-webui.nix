{ customTop, ... }:
{
  flake.modules.nixos.open-webui =
    {
      config,
      lib,
      ...
    }:
    {
      # Czyta go wyłącznie systemd (EnvironmentFile, jako root) przed startem
      # sandboxa DynamicUser — domyślne root:root 0400 wystarcza.
      # OPENAI_API_KEYS (Hermes + LLM Gateway keys) — must stay out of
      # environment {} so it never lands in the world-readable nix store.
      # Tu też WEBUI_SECRET_KEY (klucz HMAC sesji JWT; bez niego open-webui
      # generuje słaby klucz z `random` na dysku). Celowo NIE cały
      # hermes-env.age: przy ustawionym OPENAI_API_KEYS open-webui nie używa
      # OPENAI_API_KEY (config.py:336), a kompromitacja internetowego
      # open-webui (np. Functions admina) nie może dawać sekretów Hermesa.
      age.secrets.open-webui-keys.file = customTop.secretsDir + "/open-webui-keys.age";

      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        # Internal port — nginx reverse proxy listens on 8080 (cloudflared ingress target)
        port = 3001;
        environment = {
          # Własny attrset zastępuje domyślną wartość opcji modułu, więc jej
          # rezygnacje z telemetrii trzeba powtórzyć.
          SCARF_NO_ANALYTICS = "True";
          DO_NOT_TRACK = "True";
          ANONYMIZED_TELEMETRY = "False";
          # Ensure env vars always override DB-stored PersistentConfig values
          ENABLE_PERSISTENT_CONFIG = "False";
          # Publiczny adres (linki, przekierowania) zamiast domyślnego
          # http://localhost:3001 z modułu.
          WEBUI_URL = "https://chat.${customTop.site.full}";
          # OpenAI-compatible API → multiple backends. Semicolon-separated
          # lists, paired by index with OPENAI_API_KEYS (from
          # open-webui-keys.age): index 0 = Hermes Agent,
          # index 1 = LLM Gateway (devpass)
          ENABLE_OPENAI_API = "true";
          OPENAI_API_BASE_URLS = "http://127.0.0.1:8642/v1;https://api.llmgateway.io/v1";
          # Ollama API disabled — models come from Hermes Agent and
          # LLM Gateway (devpass) instead
          ENABLE_OLLAMA_API = "false";
          # Require authentication (first registered user becomes admin)
          WEBUI_AUTH = "True";
          # Konto admina już istnieje. Rejestracji nie da się wyłączyć w UI
          # (ENABLE_PERSISTENT_CONFIG=False przywraca domyślne True przy
          # każdym starcie), więc tylko tutaj.
          ENABLE_SIGNUP = "False";
          DEFAULT_USER_ROLE = "pending";
          # Stateful Responses API (forwarding previous_response_id)
          ENABLE_RESPONSES_API_STATEFUL = "1";
          # Per-connection protocol: forces BOTH OpenAI-compatible
          # connections ("0" = Hermes Agent, "1" = LLM Gateway — indexes
          # pair with OPENAI_API_BASE_URLS) into the Responses API, i.e.
          # open-webui calls each backend's /v1/responses instead of
          # /v1/chat/completions. Verified: Hermes 8642 answers /v1/responses
          # with proper Responses format; LLM Gateway exposes the endpoint
          # too (control probe: other paths 404, /v1/responses 402 billing).
          # Without this, api_type would have to be toggled per connection
          # in the web UI (Settings → Connections) — it has no env var and
          # lives only in the SQLite `config` table. With
          # ENABLE_PERSISTENT_CONFIG=False, env-driven DEFAULT_CONFIG has
          # precedence over any DB-stored per-connection settings, so this
          # is the single source of truth.
          # NOTE: write plain JSON here. NixOS already renders the unit line
          # as Environment=${builtins.toJSON "KEY=value"}, which escapes the
          # quotes for systemd itself. Hand-escaped \" got double-escaped,
          # open-webui logged "OPENAI_API_CONFIGS is not valid JSON,
          # ignoring" and silently fell back to /v1/chat/completions.
          OPENAI_API_CONFIGS = builtins.toJSON {
            "0".api_type = "responses";
            "1".api_type = "responses";
          };
          # Cookie settings: Cloudflare Tunnel terminates TLS, so the
          # browser sees HTTPS while the backend only sees HTTP on
          # 127.0.0.1. Secure=true is what fixes strict browsers (Brave,
          # Chrome strict) dropping the session cookie (open-webui#26382,
          # open-webui#15373). SameSite=lax: aplikacja jest first-party,
          # a lax działa dla XHR z tej samej domeny i przekierowań OAuth.
          # Dawne "none" razem z CORS '*' + allow_credentials pozwalało
          # dowolnej stronie wykonywać zalogowane żądania do /api/*.
          WEBUI_SESSION_COOKIE_SECURE = "true";
          WEBUI_SESSION_COOKIE_SAME_SITE = "lax";
          WEBUI_AUTH_COOKIE_SECURE = "true";
          WEBUI_AUTH_COOKIE_SAME_SITE = "lax";
          # Domyślne '*' z allow_credentials=True odbija każdy Origin.
          CORS_ALLOW_ORIGIN = "https://chat.${customTop.site.full}";
          # Nagłówki bezpieczeństwa ustawiane przez samą aplikację
          # (utils/security_headers.py) — w nginx add_header nie dziedziczy
          # się do lokacji z własnymi add_header (/_app, /static).
          XFRAME_OPTIONS = "SAMEORIGIN";
          XCONTENT_TYPE = "nosniff";
          REFERRER_POLICY = "strict-origin-when-cross-origin";
          HSTS = "max-age=31536000;includeSubDomains";
        };
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
            {
              addr = "127.0.0.1";
              port = 8080;
            }
          ];
          # Załączniki czatu i baz wiedzy: globalne 10 MB nginx odrzucało je
          # kodem 413; 100 MB = limit pojedynczego żądania w Cloudflare.
          extraConfig = ''
            client_max_body_size 100m;
          '';

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
                # Bez buforowania: odpowiedzi strumieniowe (SSE z
                # /api/chat/completions) mają dochodzić token po tokenie,
                # a nie paczkami. Backend jest lokalny, więc buforowanie
                # i tak nie chroni przed wolnym upstreamem.
                proxy_buffering off;
                # Timeouts for long-running API calls (streaming, etc.)
                proxy_read_timeout 300s;
                proxy_send_timeout 300s;
              '';
            };
          };
        };
      };

      # If open-webui ever crashes it must come back on its own — the NixOS
      # module ships Restart=no, so a single crash meant chat.janusz-bit.com
      # stayed dead until the next reboot/rebuild.
      systemd.services.open-webui.serviceConfig = {
        Restart = lib.mkForce "on-failure";
        # OPENAI_API_KEYS="<hermes key>;<llmgateway key>" i WEBUI_SECRET_KEY.
        EnvironmentFile = config.age.secrets.open-webui-keys.path;
      };

      # Ensure nginx cache directory exists with correct ownership
      systemd.tmpfiles.rules = [
        "d /var/cache/nginx/open-webui 0750 nginx nginx - -"
      ];
    };
}
