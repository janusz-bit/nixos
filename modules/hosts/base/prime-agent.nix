# Deklaratywna konfiguracja Prime Agenta (providers + default model).
# Pliki generowane do /etc/prime-agent i symlinkowane przez tmpfiles do
# ~/.prime/agent/ (domyślny katalog konfiguracji prime-agenta) — ten sam
# wzorzec co modules/skills/default.nix.
# Klucz API ollama-cloud: "OLLAMA_API_KEY" to nazwa zmiennej środowiskowej
# (prime-agent resolve'uje ją przez process.env); wartość pochodzi z agenix
# (modules/hosts/base/agenix.nix), nigdy nie trafia do /nix/store.
{
  flake.modules.nixos.base-prime-agent =
    { config, ... }:
    let
      user = config.customBot.defaultUser;

      modelsJson = builtins.toJSON {
        providers = {
          ollama = {
            baseUrl = "http://localhost:11434/v1";
            api = "openai-completions";
            # Literal "ollama" — lokalny Ollama ignoruje klucz, ale schemat go
            # wymaga (docs: packages/coding-agent/docs/models.md).
            apiKey = "ollama";
            compat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
            };
            models = [
              {
                id = "ornith:35b";
              }
              {
                # Kimi K3 (ollama cloud): thinking + vision + tools
                # (ollama show kimi-k3:cloud — Capabilities).
                id = "kimi-k3:cloud";
                reasoning = true;
                input = [
                  "text"
                  "image"
                ];
              }
            ];
          };
          ollama-cloud = {
            baseUrl = "https://ollama.com/v1";
            api = "openai-completions";
            # Nazwa zmiennej env — wartość z agenix (base/agenix.nix).
            apiKey = "OLLAMA_API_KEY";
            models = [
              {
                # DeepSeek V4.1 Flash (ollama cloud): thinking + vision + tools,
                # 1M kontekstu (ollama.com/library/deepseek-v4.1-flash, 2026-09-11).
                # Default od 2026-09-11 (ponowne wdrożenie 46e43b2, wcześniej
                # cofnięte w 4bb8f1b); glm-5.3-flash:cloud zostaje jako fallback.
                id = "deepseek-v4.1-flash:cloud";
                reasoning = true;
                input = [
                  "text"
                  "image"
                ];
              }
              {
                id = "glm-5.3-flash:cloud";
                reasoning = true;
                # Czytanie zdjęć: schemat prime-agenta dopuszcza wyłącznie
                # input ["text","image"] — modalności "video" nie ma w walidatorze
                # (docs: packages/coding-agent/docs/models.md). Filmy deklaruje
                # się tylko w opencode (modules/overlays/opencode.nix).
                input = [
                  "text"
                  "image"
                ];
              }
            ];
          };
          openrouter = {
            baseUrl = "https://openrouter.ai/api/v1";
            api = "openai-completions";
            # Nazwa zmiennej env — wartość z agenix (base/agenix.nix).
            apiKey = "OPENROUTER_API_KEY";
            models = [
              {
                # DeepSeek V4.1 Flash (OpenRouter): 1M kontekstu,
                # text+image->text, reasoning_effort + tools.
                id = "deepseek/deepseek-v4.1-flash";
                name = "DeepSeek V4.1 Flash (OpenRouter)";
                reasoning = true;
                input = [
                  "text"
                  "image"
                ];
                contextWindow = 1048576;
                maxTokens = 384000;
                # Ceny z OpenRouter (za 1M tokenów): $0.15 in / $0.60 out,
                # cache read $0.003.
                cost = {
                  input = 0.15;
                  output = 0.6;
                  cacheRead = 0.003;
                  cacheWrite = 0;
                };
              }
            ];
          };
        };
      };

      settingsJson = builtins.toJSON {
        defaultProvider = "ollama-cloud";
        defaultModel = "deepseek-v4.1-flash:cloud";
        # Wyłączona telemetria (pseudonimowe metryki użycia/wydajności —
        # nigdy bez promptów, odpowiedzi, treści narzędzi, ścieżek, repo).
        telemetry = {
          enabled = false;
        };
      };
    in
    {
      # Zmienne środowiskowe jako druga warstwa (docs telemetry):
      # PRIME_AGENT_TELEMETRY=0 nadpisuje settings, DO_NOT_TRACK=1 to
      # standard respektowany też przez inne narzędzia.
      environment.sessionVariables = {
        PRIME_AGENT_TELEMETRY = "0";
        DO_NOT_TRACK = "1";
      };

      environment.etc = {
        "prime-agent/models.json".text = modelsJson + "\n";
        "prime-agent/settings.json".text = settingsJson + "\n";
      };

      systemd.tmpfiles.rules = [
        "d /home/${user}/.prime/agent 0700 ${user} users - -"
      ]
      ++ map (name: "L+ /home/${user}/.prime/agent/${name} - - - - /etc/prime-agent/${name}") [
        "models.json"
        "settings.json"
      ];
    };
}
