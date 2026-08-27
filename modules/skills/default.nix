# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/ → instalowane do /etc/ai-skills.
# Import do Prime Agent jest automatyczny: systemd-tmpfiles symlinkuje każdy
# skill do ~/.prime/agent/skills/ (domyślny katalog skilli użytkownika, który
# Prime Agent skanuje przy każdym starcie). Dodanie nowego wpisu do `skills`
# poniżej + `nixos-rebuild switch` wystarczy — nie trzeba ręcznie edytować
# ~/.prime/agent/settings.json.
# Inne agenty (opencode, gemini-cli) celowo NIE dostają symlinków.
{
  flake.modules.nixos.ai-skills =
    {
      lib,
      config,
      ...
    }:
    let
      user = config.customBot.defaultUser or "dinosaur";

      skills = {
        ai-tutor = ./ai-tutor;
      };

      # Kopiowanie skilli do /etc/ai-skills (read-only, zarządzane przez nix).
      etcEntries = lib.mkMerge (
        lib.mapAttrsToList (name: path: {
          "ai-skills/${name}/SKILL.md".source = "${path}/SKILL.md";
          "ai-skills/${name}/references".source = "${path}/references";
        }) skills
      );

      # Automatyczny import: symlink każdego skilla do katalogu skilli Prime Agenta.
      primeSkillLinks = map (
        name: "L+ /home/${user}/.prime/agent/skills/${name} - - - - /etc/ai-skills/${name}"
      ) (lib.attrNames skills);
    in
    {
      environment.etc = etcEntries;

      systemd.tmpfiles.rules = primeSkillLinks;
    };
}
