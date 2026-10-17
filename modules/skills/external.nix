# Zewnętrzne paczki skilli (format SKILL.md) z wejść flake'a dla agentów
# kodujących stacji roboczej: Claude Code, Codex, opencode i Prime Agent.
# Obecnie Qt Development Skills od The Qt Company (wejście qt-agent-skills):
# pisanie i przegląd kodu Qt 6 C++/QML, CMake, testy Qt Quick, profilowanie
# QML, dokumentacja, design tokeny z Figmy.
#
# Każdy podkatalog paczki z SKILL.md to jeden skill. Trafia tam, gdzie agent
# szuka skilli systemowych bez konfiguracji użytkownika:
# - Claude Code: /etc/claude-code/.claude/skills/<nazwa> (skille zarządzane,
#   jak claudeSkills w ai-skills),
# - Codex: /etc/codex/skills/<nazwa> (scope ADMIN; Codex wchodzi w symlinki
#   katalogów),
# - Prime Agent: /etc/ai-skills/<nazwa> (lista skills w base/prime-agent.nix),
# - opencode: skills.paths w zarządzanym /etc/opencode/opencode.json. Ten plik
#   ma najwyższy priorytet, a opencode zastępuje (nie skleja) tablice, więc
#   własne skille opencode trzymać w ~/.config/opencode/skills/.
# Ta sama nazwa z dwóch paczek albo z paczki i z ai-skills kończy ewaluację
# błędem „conflicting definition values” dla environment.etc.
#
# Tylko laptop (import w hosts/nixos): na RPi `claude` jest też modelem
# Hermesa (claudeSubscriptionPlugin), a skille zarządzane dostaje każde konto.
# Skrypty skilli Qt wołają python3 (z desktop-ai); qmllint, qmlprofiler
# i qmltestrunner pochodzą z Qt projektu (nix develop, devenv), nie z systemu.
#
# Nowa paczka: wejście z `flake = false` we flake.nix + `nix flake lock`,
# potem jej katalog ze skillami w skillPacks niżej. Aktualizacja razem z
# resztą wejść (`flake-update`) albo osobno: `nix flake update <wejście>`.
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.nixos.config.environment.etc --apply 'e: builtins.filter (n: builtins.match "codex/.*" n != null) (builtins.attrNames e)'`;
# po aktywacji `/skills` w Claude Code i w Codexie, `opencode debug skill`.
{ inputs, ... }:
{
  flake.modules.nixos.ai-skills-external =
    { lib, ... }:
    let
      skillPacks = [
        "${inputs.qt-agent-skills}/skills"
      ];

      skillsIn =
        pack:
        lib.mapAttrsToList
          (name: _: {
            inherit name;
            source = "${pack}/${name}";
          })
          (
            lib.filterAttrs (
              name: type: type == "directory" && builtins.pathExists "${pack}/${name}/SKILL.md"
            ) (builtins.readDir pack)
          );

      skills = lib.concatMap skillsIn skillPacks;

      agentSkillDirs = [
        "claude-code/.claude/skills"
        "codex/skills"
        "ai-skills"
      ];
    in
    {
      # mkMerge zamiast `//`: ta sama nazwa to dwie definicje jednej opcji,
      # więc kolizja jest błędem, a nie cichym nadpisaniem.
      environment.etc = lib.mkMerge (
        lib.concatMap (
          dir: map (skill: { "${dir}/${skill.name}".source = skill.source; }) skills
        ) agentSkillDirs
        ++ [
          { "opencode/opencode.json".text = builtins.toJSON { skills.paths = skillPacks; }; }
        ]
      );
    };
}
