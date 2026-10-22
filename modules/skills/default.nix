# Skille agentów AI (format SKILL.md) — zarządzane deklaratywnie.
# Źródła: modules/skills/<nazwa-skill>/ → instalowane do /etc/ai-skills.
# Prime Agent czyta je bez importera: `skills` w settings.json
# (modules/hosts/base/prime-agent.nix) wymienia /etc/ai-skills i /etc/ai.
#
# /etc/ai: drop-in skilli bez rebuilda (ręcznie albo przez Prime Agenta);
# skille deklaratywne wygrywają kolizję nazw (kolejność w base/prime-agent.nix).
# Claude Code dostaje osobną listę claudeSkills. Skille z wejść flake'a (także
# dla Codexa i opencode): external.nix.
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

      # Programy, bez których skill nie działa — instalowane razem ze skillem.
      skillPackages = {
        obscura = [ pkgs.obscura ];
      };

      # Skille zarządzane Claude Code (każdy użytkownik i projekt; symlinki są
      # dozwolone, wyłączenie per proces: CLAUDE_CODE_DISABLE_POLICY_SKILLS=1).
      # Prime Agent ich nie dostaje.
      claudeSkills = {
        nixos-system = nixosSystemSkill;
      }
      # Program skilla (claude-notify) zależy od hosta, więc instaluje go
      # hosts/claude-notify.nix, a skill trafia tylko tam, gdzie ten moduł
      # wdrożył klucz.
      // lib.optionalAttrs (config.age.secrets ? hermes-notify-key) {
        hermes-notify = ./hermes-notify;
      };

      # nixos-system: statyczna treść + sekcja „This host” liczona z config
      # hosta (ręcznie pisane fakty rozjechałyby się z konfiguracją).
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
        + fact config.services.cloudflared.enable "Server: web services listen on localhost and are published only through the Cloudflare Tunnel (`services.cloudflared`); sshd also listens on the LAN."
        + fact pkgs.stdenv.hostPlatform.isAarch64 "Low-power ARM board (`nix.settings.max-jobs = ${toString config.nix.settings.max-jobs}`): avoid local builds and heavy evaluations here."
        +
          fact (config.programs.ssh.knownHosts ? laptop)
            "Laptop (host `nixos`, x86_64) is reachable when it is on and at home, from the account that holds `~/.ssh/id_ed25519_laptop` (`${user}`): `laptop-run <cmd>` runs `<cmd>` there as unprivileged `claude-remote` (no sudo) in a snapshot of the current git repo (tracked files with uncommitted changes), e.g. `laptop-run nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`, `laptop-run nixos-rebuild build --flake .#nixos` then `laptop-run nix store diff-closures /run/current-system ./result`. Prefer it to evaluating or building x86_64 hosts here. `ssh laptop <cmd>` for read-only state (`systemctl status`). Every failed login counts towards the laptop's fail2ban (5 → this host is banned). Activation stays with the user (`update-local`) — `modules/hosts/remote-agent.nix`.";

      # Skille pythonowe (src/ + pyproject.toml; każdy także w `skills`). Kernel
      # Prime Agenta to read-only env z llm-agents: bootstrap nie zrobi
      # `uv pip install` i wyłącza skill, którego nie zaimportuje, więc src/
      # trafia do PYTHONPATH wrappera prime-agent. Tylko wrappera: globalna
      # zmienna przesłaniałaby moduły innym Pythonom (venvy, uv, nix-shell).
      pythonSkills = [ "trilium-notes" ];
      pythonSkillSrcs = map (name: skills.${name} + "/src") pythonSkills;
      primeAgentWithSkills = pkgs.symlinkJoin {
        name = "prime-agent-with-skills";
        paths = [ inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.prime-agent ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/prime-agent \
            --prefix PYTHONPATH : ${lib.escapeShellArg (lib.concatStringsSep ":" pythonSkillSrcs)}
        '';
      };

      etcSkills =
        dir: lib.mapAttrs' (name: source: lib.nameValuePair "${dir}/${name}" { inherit source; });
    in
    {
      environment.etc =
        etcSkills "ai-skills" skills // etcSkills "claude-code/.claude/skills" claudeSkills;

      # hiPrio: zawinięty prime-agent wygrywa z niezawiniętym z base.
      environment.systemPackages = [
        (lib.hiPrio primeAgentWithSkills)
      ]
      ++ lib.concatLists (lib.attrValues skillPackages);

      # Zapisywalny tylko przez defaultUsera (on i jego Prime Agent dodają skille
      # bez sudo): zapis grupowy pozwoliłby kontu hermes (grupa users) podrzucić
      # skill ładowany przez prime-agenta użytkownika.
      systemd.tmpfiles.rules = [ "d /etc/ai 0755 ${user} root - -" ];
    };
}
