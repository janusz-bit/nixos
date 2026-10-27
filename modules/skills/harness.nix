# Wpina lokalne modele z customBot.modelProviders (deklaruje je ai-models,
# models.nix) do agentów kodujących: opencode2 przez zarządzany
# /etc/opencode/opencode.json (ten moduł jest jego jedynym właścicielem)
# i Prime Agenta przez customBot.primeAgentProviders (models.json buduje
# base-prime-agent). Tu jest tylko format każdego agenta, więc model
# zadeklarowany raz trafia do obu.
#
# Serwery są w konwencji llama.cpp, którą przyjmuje też Strata: tok myślenia
# w reasoning_content, reasoning_effort "none" wyłącza myślenie
# (tools/server/server-common.cpp forka PrismML, EFFORT w serve/frontend.py
# Straty), rola developer przechodzi jako system, a limit wyjścia jako
# max_completion_tokens, więc Prime Agentowi wystarcza domyślne compat.
#
# Sprawdzenie: `nix eval --raw .#nixosConfigurations.nixos.config.environment.etc."opencode/opencode.json".text`
# i to samo dla "prime-agent/models.json"; po aktywacji `opencode2 models |
# grep -E 'llamacpp/|strata/'` (modele są na liście także bez działającego
# serwera) i /model w Prime Agencie.
_: {
  flake.modules.nixos.ai-harness =
    { config, lib, ... }:
    let
      inherit (config.customBot) modelProviders;

      opencodeProvider = provider: {
        inherit (provider) name;
        package = "@opencode/ai/providers/openai-compatible";
        settings.baseURL = provider.baseUrl;
        models = lib.mapAttrs (_: model: {
          modelID = model.id;
          inherit (model) name;
          compatibility.reasoningField = "reasoning_content";
          capabilities = {
            tools = true;
            inherit (model) input;
            output = [ "text" ];
            reasoning = {
              supported = true;
              effort = model.reasoningEfforts;
            };
          };
          limit = {
            inherit (model) context output;
          };
        }) provider.models;
      };

      primeProvider = name: provider: {
        inherit (provider) baseUrl;
        api = "openai-completions";
        # Schemat Prime wymaga klucza; serwer bez klucza go ignoruje.
        apiKey = name;
        models = lib.mapAttrsToList (_: model: {
          inherit (model) id name input;
          reasoning = true;
          # Poziom spoza reasoningEfforts dostaje null: Prime go wyłącza
          # i dobiera najbliższy.
          thinkingLevelMap = {
            off = "none";
          }
          // lib.genAttrs [ "minimal" "low" "medium" "high" "xhigh" "max" ] (
            level: if lib.elem level model.reasoningEfforts then level else null
          );
          contextWindow = model.context;
          maxTokens = model.output;
        }) provider.models;
      };
    in
    {
      customBot.primeAgentProviders = lib.mapAttrs primeProvider modelProviders;

      environment.etc."opencode/opencode.json".text = builtins.toJSON {
        providers = lib.mapAttrs (_: opencodeProvider) modelProviders;
      };
    };
}
