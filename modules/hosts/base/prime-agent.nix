# Deklaratywna konfiguracja Prime Agenta: models.json (providerzy, także
# customBot.primeAgentProviders hosta) i settings.json w /etc/prime-agent,
# linkowane przez tmpfiles do ~/.prime/agent/ głównego użytkownika.
#
# apiKey i bearerTokenEnvVar to nazwy zmiennych env (prime-agent czyta je
# z process.env); wartości wstrzykuje wrapper prime-agent z base-agenix, więc
# żaden klucz nie trafia do /nix/store.
{ inputs, ... }:
{
  flake.modules.nixos.base-prime-agent =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.customBot.defaultUser;
      agentDir = "${config.users.users.${user}.home}/.prime/agent";

      # Thinking + obraz na wejściu (modele Ollamy: `ollama show <model>`,
      # Capabilities). Schemat prime-agenta dopuszcza tylko input
      # ["text","image"] — modalności "video" nie ma w walidatorze.
      reasoningModel = id: {
        inherit id;
        reasoning = true;
        input = [
          "text"
          "image"
        ];
      };

      models = {
        # unionOfDisjoint zamiast `//`: provider hosta o nazwie wspólnej z tymi
        # niżej kończy ewaluację, zamiast po cichu zastąpić wspólnego.
        providers = lib.attrsets.unionOfDisjoint config.customBot.primeAgentProviders {
          ollama = {
            baseUrl = "http://localhost:11434/v1";
            api = "openai-completions";
            # Literał, nie nazwa zmiennej: lokalny Ollama ignoruje klucz, ale
            # schemat go wymaga.
            apiKey = "ollama";
            compat = {
              supportsDeveloperRole = false;
              supportsReasoningEffort = false;
            };
            models = [
              { id = "ornith:35b"; }
              (reasoningModel "kimi-k3:cloud")
            ];
          };
          ollama-cloud = {
            baseUrl = "https://ollama.com/v1";
            api = "openai-completions";
            apiKey = "OLLAMA_API_KEY";
            models = [
              (reasoningModel "deepseek-v4.1-flash:cloud")
              (reasoningModel "glm-5.3-flash:cloud")
            ];
          };
          openrouter = {
            baseUrl = "https://openrouter.ai/api/v1";
            api = "openai-completions";
            apiKey = "OPENROUTER_API_KEY";
            models = [
              (
                reasoningModel "deepseek/deepseek-v4.1-flash"
                // {
                  name = "DeepSeek V4.1 Flash (OpenRouter)";
                  contextWindow = 1048576;
                  maxTokens = 384000;
                  # USD za 1M tokenów (cennik OpenRouter).
                  cost = {
                    input = 0.15;
                    output = 0.6;
                    cacheRead = 0.003;
                    cacheWrite = 0;
                  };
                }
              )
            ];
          };
        };
      };

      settings = {
        defaultProvider = "ollama-cloud";
        defaultModel = "glm-5.3-flash:cloud";
        telemetry.enabled = false;
        # Przy kolizji nazw wygrywa wcześniejszy katalog, więc deklaratywne
        # skille (ai-skills) mają pierwszeństwo przed drop-inem /etc/ai;
        # brakujący katalog (WSL bez ai-skills) prime-agent pomija.
        skills = [
          "/etc/ai-skills"
          "/etc/ai"
        ];
        # Token tylko przez zmienną env — literalne sekrety prime-agent odrzuca.
        mcpServers.trilium-notes = {
          type = "http";
          url = config.customBot.triliumMcpUrl;
          bearerTokenEnvVar = "TRILIUM_ETAPI_TOKEN";
        };
      };
    in
    {
      environment = {
        # Hosty z ai-skills dokładają wariant z PYTHONPATH skilli (hiPrio,
        # modules/skills/default.nix).
        systemPackages = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent ];

        sessionVariables = {
          # Druga warstwa obok settings.telemetry; PRIME_AGENT_TELEMETRY=0
          # nadpisuje settings, DO_NOT_TRACK=1 respektują też inne narzędzia.
          PRIME_AGENT_TELEMETRY = "0";
          DO_NOT_TRACK = "1";
          # Skill trilium-notes — ten sam endpoint co mcpServers.
          TRILIUM_MCP_URL = config.customBot.triliumMcpUrl;
        };

        etc = {
          "prime-agent/models.json".text = builtins.toJSON models + "\n";
          "prime-agent/settings.json".text = builtins.toJSON settings + "\n";
        };
      };

      systemd.tmpfiles.rules = [
        "d ${agentDir} 0700 ${user} users - -"
      ]
      ++ map (name: "L+ ${agentDir}/${name} - - - - /etc/prime-agent/${name}") [
        "models.json"
        "settings.json"
      ];
    };
}
