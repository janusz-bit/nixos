# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/ → instalowane do /etc/ai-skills.
# Prime Agent czyta je bez importera: `skills` w settings.json
# (modules/hosts/base/prime-agent.nix) wymienia /etc/ai-skills i /etc/ai.
#
# Runtime drop-in: /etc/ai to katalog na skille dodawane BEZ rebuilda (ręcznie
# lub przez samego Prime Agenta), widoczne przy następnym starcie agenta.
# Przy kolizji nazw wygrywa wcześniejszy wpis listy, więc skille deklaratywne
# (/etc/ai-skills) mają pierwszeństwo przed /etc/ai: nix pozostaje źródłem
# prawdy. Inne agenty (opencode, gemini-cli) tych katalogów nie czytają.
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

      skills = {
        ai-tutor = ./ai-tutor;
        trilium-notes = ./trilium-notes;
        obscura = ./obscura;
      };

      # Programy, bez których skill nie działa — instalowane przez ten moduł
      # razem ze skillem, żeby skill nie trafił na host bez swojego narzędzia.
      skillPackages = {
        obscura = [ pkgs.obscura ];
      };

      # Skille Claude Code (format SKILL.md jak wyżej). Claude Code na Linuksie
      # ładuje skille zarządzane z /etc/claude-code/.claude/skills/<nazwa>
      # (`claude --debug`: „Loading skills from: managed=…”), dla każdego
      # użytkownika i projektu; symlinki są dozwolone. Wyłączenie per proces:
      # CLAUDE_CODE_DISABLE_POLICY_SKILLS=1. Prime Agent ich nie dostaje.
      claudeSkills = {
        nixos-system = nixosSystemSkill;
      }
      # Program skilla (claude-notify) zależy od hosta, więc jest w
      # modules/hosts/raspberry-pi-4/hermes-notify.nix, nie w skillPackages —
      # skill tylko tam, gdzie ten moduł wdrożył klucz.
      // lib.optionalAttrs (config.age.secrets ? hermes-notify-key) {
        hermes-notify = ./hermes-notify;
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
        +
          fact (config.services.hermes-agent.enable or false)
            "Hermes Agent runs as the unprivileged account `hermes` (no sudo, no `wheel`); its state `${config.services.hermes-agent.stateDir}` is shared with `${user}` through the `hermes` group. Run its CLI only through the `hermes` wrapper — never the package binary as root or `${user}` (`modules/hosts/raspberry-pi-4/hermes.nix`)."
        + fact config.services.cloudflared.enable "Server: services bind to localhost and are published only through the Cloudflare Tunnel (`services.cloudflared`)."
        + fact pkgs.stdenv.hostPlatform.isAarch64 "Low-power ARM board (`nix.settings.max-jobs = ${toString config.nix.settings.max-jobs}`): avoid local builds and heavy evaluations here."
        +
          fact (config.programs.ssh.knownHosts ? laptop)
            "Laptop (host `nixos`, x86_64) is reachable when it is on and at home, from the account that holds `~/.ssh/id_ed25519_laptop` (`${user}`): `laptop-run <cmd>` runs `<cmd>` there as unprivileged `claude-remote` (no sudo) in a snapshot of the current git repo (tracked files with uncommitted changes), e.g. `laptop-run nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`, `laptop-run nixos-rebuild build --flake .#nixos` then `laptop-run nix store diff-closures /run/current-system ./result`. Prefer it to evaluating or building x86_64 hosts here. `ssh laptop <cmd>` for read-only state (`systemctl status`). Every failed login counts towards the laptop's fail2ban (5 → this host is banned). Activation stays with the user (`update-local`) — `modules/hosts/nixos/remote-agent.nix`.";

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
    in
    {
      environment.etc = lib.mkMerge [
        etcEntries
        (lib.mapAttrs' (
          name: path: lib.nameValuePair "claude-code/.claude/skills/${name}" { source = path; }
        ) claudeSkills)
      ];

      # Import skili pythonowych w kernelu (patrz pythonSkills wyżej).
      environment.systemPackages = [
        (lib.hiPrio primeAgentWithSkills)
      ]
      ++ lib.concatLists (lib.attrValues skillPackages);

      # Drop-in na skille runtime — zapisywalny tylko przez defaultUsera
      # (on i jego Prime Agent dodają skille bez sudo). Wcześniej 0775
      # root:users: na RPi agent hermes (grupa users) mógł podrzucić skill
      # ładowany automatycznie przez prime-agenta użytkownika nixos.
      systemd.tmpfiles.rules = [ "d /etc/ai 0755 ${user} root - -" ];
    };
}
