# Deklaratywna konfiguracja Prime Agenta: settings.json i models.json
# w /etc/prime-agent, linkowane przez tmpfiles do ~/.prime/agent/ głównego
# użytkownika. models.json (providerzy i modele) powstaje z opcji ai.models
# w ai-harness (modules/ai/harness.nix).
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

      settings = {
        defaultProvider = "ollama-cloud";
        defaultModel = "glm-5.3-flash:cloud";
        telemetry.enabled = false;
        # Przy kolizji nazw wygrywa wcześniejszy katalog, więc deklaratywne
        # skille (ai-harness) mają pierwszeństwo przed drop-inem /etc/ai;
        # brakujący katalog (WSL bez skilli) prime-agent pomija.
        skills = [
          "/etc/ai-skills"
          "/etc/ai"
        ];
        # Tylko na hoście z Trilium (customBot.triliumMcpUrl). Token tylko przez
        # zmienną env — literalne sekrety prime-agent odrzuca.
        mcpServers = lib.optionalAttrs (config.customBot.triliumMcpUrl != null) {
          trilium-notes = {
            type = "http";
            url = config.customBot.triliumMcpUrl;
            bearerTokenEnvVar = "TRILIUM_ETAPI_TOKEN";
          };
        };
      };
    in
    {
      environment = {
        # Host ze skillem pythonowym dokłada wariant z PYTHONPATH skilli
        # (hiPrio, modules/ai/harness.nix).
        systemPackages = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent ];

        sessionVariables = {
          # Druga warstwa obok settings.telemetry; PRIME_AGENT_TELEMETRY=0
          # nadpisuje settings, DO_NOT_TRACK=1 respektują też inne narzędzia.
          PRIME_AGENT_TELEMETRY = "0";
          DO_NOT_TRACK = "1";
          # Skill trilium-notes — ten sam endpoint co mcpServers.
          TRILIUM_MCP_URL = lib.mkIf (config.customBot.triliumMcpUrl != null) config.customBot.triliumMcpUrl;
        };

        etc."prime-agent/settings.json".text = builtins.toJSON settings + "\n";
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
