{
  flake.modules.nixos.prime-agent-bridge =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      # ─────────────────────────────────────────────────────────────
      # Prime Agent jako trzeci backend open-webui
      #
      # Prime Agent to CLI bez serwera HTTP (tryby rpc/json/daemon są
      # tylko lokalne/stdin), więc ten mały mostek (pakiet
      # prime-agent-bridge: stdlib Python, bez zależności) tłumaczy
      # OpenAI /v1/chat/completions na jednorazowe wywołania
      # `prime-agent --print --mode json`. open-webui widzi go jako
      # index 2 w OPENAI_API_BASE_URLS (port 8643, patrz open-webui.nix).
      # Bez auth — słucha wyłącznie na 127.0.0.1, tak jak Hermes (8642).
      # ─────────────────────────────────────────────────────────────

      # Dedykowany użytkownik z trwałym HOME: wrapper prime-agent
      # seeduje ~/.prime/agent/ (models.json, skille) przy pierwszym
      # starcie, a kernel IPython (RLM) bootstrapuje venv przez uv —
      # oba potrzebują zapisywalnego katalogu domowego.
      users.users.prime-bridge = {
        isSystemUser = true;
        group = "prime-bridge";
        home = "/var/lib/prime-bridge";
        createHome = true;
      };
      users.groups.prime-bridge = { };

      systemd.services.prime-agent-bridge = {
        description = "OpenAI-compatible HTTP bridge for Prime Agent CLI";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "simple";
          User = "prime-bridge";
          Group = "prime-bridge";
          ExecStart = lib.getExe pkgs.prime-agent-bridge;
          Environment = [
            "PRIME_AGENT_BIN=${lib.getExe pkgs.prime-agent}"
            "PRIME_BRIDGE_HOST=127.0.0.1"
            "PRIME_BRIDGE_PORT=8643"
            # open-webui ma twardy limit 300 s na request (AIOHTTP_CLIENT_TIMEOUT),
            # więc mostek musi skończyć wcześniej niż on
            "PRIME_BRIDGE_TIMEOUT=280"
            "HOME=/var/lib/prime-bridge"
            "UV_CACHE_DIR=/var/lib/prime-bridge/.cache/uv"
          ];
          # LLMGATEWAY_API_KEY (root:users 0440, czytane przez systemd
          # jako root przed zrzutem uprawnień). prime-agent czyta ten
          # env, bo apiKey w seedowanym models.json to NAZWA zmiennej —
          # sekret nigdy nie trafia do store.
          EnvironmentFile = config.age.secrets.llmgateway-api-key-shared.path;
          Restart = "on-failure";
          RestartSec = 5;
          # Hardening: tylko localhost, bez uprawnień, zapis wyłącznie
          # we własnym HOME.
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ "/var/lib/prime-bridge" ];
        };
      };
    };
}
