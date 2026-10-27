# Zewnętrzne paczki skilli (SKILL.md) z wejść flake'a dla Claude Code, Codexa,
# opencode i Prime Agenta; obecnie Qt Development Skills (wejście
# qt-agent-skills: Qt 6 C++/QML, CMake, testy Qt Quick, profilowanie QML,
# design tokeny z Figmy) i tstack (wejście tstack: prowadzenie PR przez
# review i CI do merge'a, przez gh).
#
# Każdy podkatalog paczki z SKILL.md to jeden skill w customBot.agentSkills;
# ai-skills (modules/skills/default.nix) linkuje go do katalogów skilli
# systemowych każdego agenta. Ta sama nazwa z dwóch paczek albo z paczki
# i z ai-skills kończy ewaluację błędem „conflicting definition values”.
#
# Tylko laptop (import w hosts/nixos): skille Qt są narzędziami stacji
# roboczej. Skrypty skilli Qt i pr-wait z babysit-pr wołają python3
# (desktop-ai), skille tstack także gh (base-git); council i sol-loop
# potrzebują subagentów na modelach innych dostawców.
# qmllint, qmlprofiler i qmltestrunner pochodzą z Qt projektu (nix develop,
# devenv), nie z systemu.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.environment.etc --apply 'e: builtins.filter (n: builtins.match "codex/.*" n != null) (builtins.attrNames e)'`;
# po aktywacji `/skills` w Claude Code i w Codexie.
{ inputs, ... }:
{
  flake.modules.nixos.ai-skills-external =
    { lib, ... }:
    let
      skillPacks = [
        "${inputs.qt-agent-skills}/skills"
        "${inputs.tstack}/skills"
      ];

      skillsIn =
        pack:
        lib.mapAttrs (name: _: "${pack}/${name}") (
          lib.filterAttrs (
            name: type: type == "directory" && builtins.pathExists "${pack}/${name}/SKILL.md"
          ) (builtins.readDir pack)
        );
    in
    {
      # Każda paczka to osobna definicja opcji, więc ta sama nazwa w dwóch
      # paczkach jest błędem, a nie cichym nadpisaniem.
      customBot.agentSkills = lib.mkMerge (map skillsIn skillPacks);
    };
}
