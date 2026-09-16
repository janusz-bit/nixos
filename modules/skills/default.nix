# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/ → instalowane do /etc/ai-skills.
# Import do Prime Agent jest automatyczny: systemd-tmpfiles symlinkuje każdy
# skill do ~/.prime/agent/skills/ (domyślny katalog skilli użytkownika, który
# Prime Agent skanuje przy każdym starcie). Dodanie nowego wpisu do `skills`
# poniżej + `nixos-rebuild switch` wystarczy — nie trzeba ręcznie edytować
# ~/.prime/agent/settings.json.
#
# Runtime drop-in: /etc/ai to katalog na skille dodawane BEZ rebuilda (ręcznie
# lub przez samego Prime Agenta). Usługa prime-agent-skills-import.service
# (oneshot przy boocie + systemd.path nasłuchujący na zmiany w /etc/ai)
# symlinkuje każdy podkatalog zawierający SKILL.md do ~/.prime/agent/skills/.
# Usunięcie skilla z /etc/ai sprząta jego symlink. Skille deklaratywne
# (linki do /etc/ai-skills) mają pierwszeństwo — importer nigdy ich nie
# nadpisuje: nix pozostaje źródłem prawdy.
# Inne agenty (opencode, gemini-cli) celowo NIE dostają symlinków.
{
  flake.modules.nixos.ai-skills =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      user = config.customBot.defaultUser or "dinosaur";

      skills = {
        ai-tutor = ./ai-tutor;
        trilium-notes = ./trilium-notes;
        obscura = ./obscura;
      };

      # Skille pythonowe (src/ + pyproject.toml). Kernel Prime Agenta działa na
      # PRIME_AGENT_KERNEL_PYTHON (read-only env z flake llm-agents), więc
      # bootstrap NIE zrobi `uv pip install --editable` — tylko sprawdza
      # `import <skill>` i wyłącza skill z warningiem, gdy import się nie uda.
      # Dlatego src/ trafia do PYTHONPATH (sessionVariables -> prime-agent ->
      # kernel) i skill jest importowalny out-of-the-box. Nowy skill pythonowy:
      # dodaj do `skills` ORAZ do `pythonSkills`.
      pythonSkills = [ "trilium-notes" ];
      pythonSkillSrcs = map (name: skills.${name} + "/src") pythonSkills;

      # Kopiowanie skilli do /etc/ai-skills (read-only, zarządzane przez nix).
      # Cały katalog skilla: SKILL.md, references/, a przy skillach pythonowych
      # też src/ + pyproject.toml (kernel Prime Agenta importuje je z PYTHONPATH,
      # bo PRIME_AGENT_KERNEL_PYTHON to read-only env — bez uv pip install).
      etcEntries = lib.mkMerge (
        lib.mapAttrsToList (name: path: {
          "ai-skills/${name}".source = path;
        }) skills
      );

      # Automatyczny import: symlink każdego skilla do katalogu skilli Prime Agenta.
      primeSkillLinks = map (
        name: "L+ /home/${user}/.prime/agent/skills/${name} - - - - /etc/ai-skills/${name}"
      ) (lib.attrNames skills);

      primeSkillsDir = "/home/${user}/.prime/agent/skills";

      # Import skilli z katalogu drop-in /etc/ai:
      # 1. symlink każdego podkatalogu z SKILL.md do katalogu skilli Prime Agenta,
      # 2. sprzątanie linków wskazujących na usunięte/niepełne skille z /etc/ai.
      importScript = pkgs.writeShellScript "prime-agent-skills-import" ''
        set -eu
        export PATH="${pkgs.coreutils}/bin"

        skills_dir="${primeSkillsDir}"
        drop_in="/etc/ai"

        mkdir -p "$skills_dir"

        # 1. Import/odświeżenie linków ze skilli w /etc/ai.
        for src in "$drop_in"/*; do
          [ -d "$src" ] || continue
          name=$(basename "$src")
          [ -f "$src/SKILL.md" ] || continue
          link="$skills_dir/$name"
          # Skille deklaratywne wygrywają — nie ruszaj linków do /etc/ai-skills.
          if [ -L "$link" ] && [ "$(readlink "$link")" = "/etc/ai-skills/$name" ]; then
            continue
          fi
          if [ -e "$link" ] && [ ! -L "$link" ]; then
            echo "prime-agent-skills-import: pomijam $name — $link nie jest symlinkiem" >&2
            continue
          fi
          ln -sfn "$src" "$link"
          echo "prime-agent-skills-import: zaimportowano skill $name"
        done

        # 2. Sprzątanie: linki do /etc/ai/<name>, które już nie istnieją
        #    lub nie zawierają SKILL.md.
        for link in "$skills_dir"/*; do
          [ -L "$link" ] || continue
          target=$(readlink "$link")
          case "$target" in
            "$drop_in"/*)
              if [ ! -f "$target/SKILL.md" ]; then
                rm -f -- "$link"
                echo "prime-agent-skills-import: usunięto nieaktualny link $(basename "$link")"
              fi
              ;;
          esac
        done
      '';
    in
    {
      environment.etc = etcEntries;

      # Import skili pythonowych w kernelu (patrz pythonSkills wyżej).
      environment.sessionVariables.PYTHONPATH = lib.concatStringsSep ":" pythonSkillSrcs;

      systemd = {
        tmpfiles.rules = [
          # Drop-in na skille runtime; grupa users może dodawać skille bez sudo.
          "d /etc/ai 0775 root users - -"
          # Katalog skilli Prime Agenta zapisywalny przez usługę (User = user).
          # Bez tego tmpfiles utworzy go jako root i importer nie zapisze linku.
          "d ${primeSkillsDir} 0755 ${user} users - -"
        ]
        ++ primeSkillLinks;

        services.prime-agent-skills-import = {
          description = "Import AI skills from /etc/ai into Prime Agent";
          wantedBy = [ "multi-user.target" ];
          after = [
            "local-fs.target"
            "systemd-tmpfiles-setup.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            User = user;
            ExecStart = importScript;
            NoNewPrivileges = true;
            PrivateTmp = true;
            ProtectSystem = "strict";
            ReadWritePaths = [ "/home/${user}/.prime/agent" ];
          };
        };

        # Reakcja na zmiany w /etc/ai bez restartu systemu i bez rebuilda.
        paths.prime-agent-skills-import = {
          description = "Watch /etc/ai for AI skill changes";
          wantedBy = [ "multi-user.target" ];
          pathConfig = {
            PathChanged = "/etc/ai";
          };
        };
      };
    };
}
