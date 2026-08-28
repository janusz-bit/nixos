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
            ];
          };
          ollama-cloud = {
            baseUrl = "https://ollama.com/v1";
            api = "openai-completions";
            # Nazwa zmiennej env — wartość z agenix (base/agenix.nix).
            apiKey = "OLLAMA_API_KEY";
            models = [
              {
                id = "glm-5.3-flash:cloud";
                reasoning = true;
              }
            ];
          };
        };
      };

      settingsJson = builtins.toJSON {
        defaultProvider = "ollama-cloud";
        defaultModel = "glm-5.3-flash:cloud";
      };
    in
    {
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
