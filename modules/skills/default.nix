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
#
# Claude Code: osobna lista `claudeSkills` → /etc/claude-code/.claude/skills,
# katalog skilli zarządzanych (policy) czytany przez każdego użytkownika hosta
# w każdym katalogu roboczym — bez Home Managera i bez ~/.claude/skills.
{ inputs, ... }:
{
  flake.modules.nixos.ai-skills =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      user = config.customBot.defaultUser;
      primeAgentDir = "${config.users.users.${user}.home}/.prime/agent";

      skills = {
        ai-tutor = ./ai-tutor;
        trilium-notes = ./trilium-notes;
        obscura = ./obscura;
      };

      # Skille Claude Code (format SKILL.md jak wyżej). Claude Code na Linuksie
      # ładuje skille zarządzane z /etc/claude-code/.claude/skills/<nazwa>
      # (`claude --debug`: „Loading skills from: managed=…”), dla każdego
      # użytkownika i projektu; symlinki są dozwolone. Wyłączenie per proces:
      # CLAUDE_CODE_DISABLE_POLICY_SKILLS=1. Prime Agent ich nie dostaje.
      claudeSkills = {
        nixos-system = nixosSystemSkill;
      };

      # nixos-system: statyczna treść + sekcja „This host” liczona z config
      # hosta, na którym skill jest wdrożony (laptop i RPi dostają różne
      # fakty, a ręcznie pisane rozjechałyby się z konfiguracją).
      nixosSystemSkill = pkgs.writeTextDir "SKILL.md" (
        builtins.readFile ./nixos-system/SKILL.md + nixosSystemHostFacts
      );

      nixosSystemHostFacts =
        let
          inherit (config.system.nixos) release;
          nixLdLibs = lib.concatMapStringsSep ", " lib.getName config.programs.nix-ld.libraries;
          fact = cond: text: lib.optionalString cond "- ${text}\n";
        in
        "\n## This host\n\n"
        + "Generated from the flake at build time (`modules/skills/default.nix`).\n\n"
        + fact true "Hostname `${config.networking.hostName}`, flake output `nixosConfigurations.${config.customBot.flakeTarget}`, platform `${pkgs.stdenv.hostPlatform.system}`."
        + fact true "NixOS ${release}, `system.stateVersion = \"${config.system.stateVersion}\"` (never change it), kernel ${config.boot.kernelPackages.kernel.version}."
        + fact true "Main interactive user: `${user}`."
        + fact config.programs.nix-ld.enable "nix-ld libraries (all a prebuilt binary can find): ${nixLdLibs}."
        + fact config.services.desktopManager.plasma6.enable "Desktop: KDE Plasma 6 on Wayland, no X server (Xwayland only)."
        + fact config.hardware.nvidia.prime.offload.enableOffloadCmd "Hybrid GPU (NVIDIA PRIME offload): integrated GPU by default, `nvidia-offload <cmd>` runs a program on the NVIDIA dGPU."
        + fact config.virtualisation.podman.enable "Rootless podman${lib.optionalString config.virtualisation.podman.dockerCompat " (`docker` = podman wrapper)"}; no Docker daemon."
        + fact config.services.ollama.enable "Ollama listens on `${config.services.ollama.host}:${toString config.services.ollama.port}`."
        + fact config.services.cloudflared.enable "Server: services bind to localhost and are published only through the Cloudflare Tunnel (`services.cloudflared`)."
        + fact pkgs.stdenv.hostPlatform.isAarch64 "Low-power ARM board (`nix.settings.max-jobs = ${toString config.nix.settings.max-jobs}`): avoid local builds and heavy evaluations here.";

      # Skille pythonowe (src/ + pyproject.toml). Kernel Prime Agenta działa na
      # PRIME_AGENT_KERNEL_PYTHON (read-only env z flake llm-agents), więc
      # bootstrap NIE zrobi `uv pip install --editable` — tylko sprawdza
      # `import <skill>` i wyłącza skill z warningiem, gdy import się nie uda.
      # Dlatego src/ trafia do PYTHONPATH wrappera prime-agenta (-> kernel) i
      # skill jest importowalny out-of-the-box. Nowy skill pythonowy:
      # dodaj do `skills` ORAZ do `pythonSkills`.
      pythonSkills = [ "trilium-notes" ];
      pythonSkillSrcs = map (name: skills.${name} + "/src") pythonSkills;

      # PYTHONPATH tylko dla prime-agenta — globalna zmienna sesji trafiałaby
      # do każdego procesu Pythona (venvy, uv, nix-shell) i mogła przesłaniać
      # moduły. hiPrio: wygrywa z niezawiniętym prime-agentem z base.
      primeAgentWithSkills = pkgs.symlinkJoin {
        name = "prime-agent-with-skills";
        paths = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/prime-agent \
            --prefix PYTHONPATH : ${lib.escapeShellArg (lib.concatStringsSep ":" pythonSkillSrcs)}
        '';
      };

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
      primeSkillLinks = map (name: "L+ ${primeSkillsDir}/${name} - - - - /etc/ai-skills/${name}") (
        lib.attrNames skills
      );

      primeSkillsDir = "${primeAgentDir}/skills";

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
      environment.etc = lib.mkMerge [
        etcEntries
        (lib.mapAttrs' (
          name: path: lib.nameValuePair "claude-code/.claude/skills/${name}" { source = path; }
        ) claudeSkills)
      ];

      # Import skili pythonowych w kernelu (patrz pythonSkills wyżej).
      environment.systemPackages = [ (lib.hiPrio primeAgentWithSkills) ];

      systemd = {
        tmpfiles.rules = [
          # Drop-in na skille runtime — zapisywalny tylko przez defaultUsera
          # (on i jego Prime Agent dodają skille bez sudo). Wcześniej 0775
          # root:users: na RPi agent hermes (grupa users) mógł podrzucić skill
          # ładowany automatycznie przez prime-agenta użytkownika nixos.
          "d /etc/ai 0755 ${user} root - -"
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
            ReadWritePaths = [ primeAgentDir ];
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
