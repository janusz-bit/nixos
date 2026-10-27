# Modele agentów AI wspólne dla każdego hosta: lokalna Ollama (także modele
# chmurowe przez nią), Ollama Cloud i OpenRouter dla Prime Agenta. Wybór
# z katalogu w modules/ai/models.nix; skille i modele tylko jednego hosta
# włącza jego własny ai.nix.
_: {
  flake.modules.nixos.base-ai = _: {
    ai.models = {
      ollama-ornith-35b.enable = true;
      ollama-kimi-k3-cloud.enable = true;
      ollama-cloud-deepseek-v4-1-flash.enable = true;
      ollama-cloud-glm-5-3-flash.enable = true;
      openrouter-deepseek-v4-1-flash.enable = true;
    };
  };
}
