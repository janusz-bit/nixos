# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/  → instalowane do /etc/ai-skills
#         + symlinki do katalogów czytanych przez agentów (opencode, gemini-cli).
{ config, ... }:
{
  flake.modules.nixos.ai-skills =
    { lib, ... }:
    {
      environment.etc =
        let
          skills = {
            ai-tutor = ./ai-tutor;
          };
          # Wspólne pliki każdego skilla (opcjonalne, poza SKILL.md)
          extraFiles = [ "templates.md" ];
        in
        lib.mkMerge (
          lib.mapAttrsToList (
            name: path:
            {
              "ai-skills/${name}/SKILL.md".source = "${path}/SKILL.md";
            }
            // lib.listToAttrs (
              map (file: {
                name = "ai-skills/${name}/${file}";
                value.source = lib.mkIf (builtins.pathExists "${path}/${file}") "${path}/${file}";
              }) extraFiles
            )
          ) skills
        );

      systemd.tmpfiles.rules =
        let
          user = "dinosaur";
          home = "/home/${user}";
          skillNames = [ "ai-tutor" ];
        in
        # OpenCode: ~/.config/opencode/skill/<name>/
        map (name: "L+ ${home}/.config/opencode/skill/${name} - - - - /etc/ai-skills/${name}") skillNames
        # Gemini CLI: ~/.gemini/skills/<name>/
        ++ map (name: "L+ ${home}/.gemini/skills/${name} - - - - /etc/ai-skills/${name}") skillNames;
    };
}
