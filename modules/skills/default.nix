# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/ → instalowane do /etc/ai-skills.
# Skille z /etc/ai-skills są dostępne WYŁĄCZNIE dla Prime Agent
# (odczyt konfigurowany w ~/.prime/agent/settings.json → "skills").
# Inne agenty (opencode, gemini-cli) celowo NIE dostają symlinków.
{
  flake.modules.nixos.ai-skills =
    { lib, ... }:
    {
      environment.etc =
        let
          skills = {
            ai-tutor = ./ai-tutor;
          };
        in
        lib.mkMerge (
          lib.mapAttrsToList (name: path: {
            "ai-skills/${name}/SKILL.md".source = "${path}/SKILL.md";
            "ai-skills/${name}/references".source = "${path}/references";
          }) skills
        );
    };
}
