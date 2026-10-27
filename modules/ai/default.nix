# Agregat ai: skille i modele agentów kodujących (Prime Agent, Claude Code,
# Codex, opencode2) w stylu opcji NixOS. ai-options deklaruje opcje ai.*,
# ai-skills i ai-models mają definicje skilli i modeli (katalogi bez
# włączania), ai-harness przekłada wybrane na konfigurację agentów; hosty
# wybierają w ai.nix (`base-ai`, `nixos-ai`, `rpi-ai`) same `enable`. Importuje
# go base, więc każdy host ma opcje, ale pliki trafiają do agentów tylko dla
# tego, co host włączył.
{ self, ... }:
{
  flake.modules.nixos.ai = _: {
    imports = [
      self.modules.nixos.ai-options
      self.modules.nixos.ai-skills
      self.modules.nixos.ai-models
      self.modules.nixos.ai-harness
    ];
  };
}
