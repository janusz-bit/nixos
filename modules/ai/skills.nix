# Katalog skilli agentów AI: które skille repozytorium zna (ai.skills) i skąd
# pochodzą paczki skilli z wejść flake'a (ai.skillPacks; Qt Development Skills
# z wejścia qt-agent-skills i tstack, czyli prowadzenie PR przez review i CI
# do merge'a przez gh). Same skille leżą w modules/skills/<nazwa>/ (SKILL.md +
# references/; skill pythonowy też src/ i pyproject.toml); tu tylko wpisy, bez
# włączania: host wybiera je w swoim ai.nix, a ai-harness linkuje wybrane do
# agentów.
#
# Skrypty skilli Qt i pr-wait z babysit-pr wołają python3 (desktop-ai), skille
# tstack także gh (base-git); council i sol-loop potrzebują subagentów na
# modelach innych dostawców. qmllint, qmlprofiler i qmltestrunner pochodzą
# z Qt projektu (nix develop, devenv), nie z systemu.
#
# Nowy skill: katalog w modules/skills/, wpis w ai.skills niżej (agents, gdy
# działa tylko w jednym agencie; python = true dla skilla pythonowego;
# packages dla programów, które woła) i `ai.skills.<nazwa>.enable = true;`
# w ai.nix hosta. Nowa paczka: wejście `flake = false` w flake.nix +
# `nix flake lock`, wpis w ai.skillPacks i enable; flake-update aktualizuje ją
# z pozostałymi wejściami (jedną: `nix flake update <wejście>`).
#
# Sprawdzenie: `nix eval --json .#nixosConfigurations.<host>.config.environment.etc --apply 'e: builtins.filter (n: builtins.match "(ai-skills|claude-code/.claude/skills|codex/skills|opencode/skills)/.*" n != null) (builtins.attrNames e)'`;
# po aktywacji `/skills` w Claude Code i w Codexie, w opencode2
# `opencode2 api skill.list` dwa razy (pierwsze wywołanie w nowym katalogu
# zwraca pustą listę, zanim serwer wczyta skille).
{ inputs, self, ... }:
{
  flake.modules.nixos.ai-skills =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      user = config.customBot.defaultUser;
      brulionPackage = inputs.brulion.packages.${pkgs.stdenv.hostPlatform.system}.default;

      # nixos-system: statyczna treść + sekcja „This host” liczona z config
      # hosta, na którym skill jest wdrożony (laptop i RPi dostają różne
      # fakty, a ręcznie pisane rozjechałyby się z konfiguracją).
      nixosSystemSkill = pkgs.writeTextDir "SKILL.md" (
        builtins.readFile "${self}/modules/skills/nixos-system/SKILL.md" + nixosSystemHostFacts
      );

      nixosSystemHostFacts =
        let
          nixLdLibs = lib.concatMapStringsSep ", " lib.getName config.programs.nix-ld.libraries;
          fact = cond: text: lib.optionalString cond "- ${text}\n";
        in
        "\n## This host\n\n"
        + "Generated from the flake at build time (`modules/ai/skills.nix`).\n\n"
        + fact true "Hostname `${config.networking.hostName}`, flake output `nixosConfigurations.${config.customBot.flakeTarget}`, platform `${pkgs.stdenv.hostPlatform.system}`."
        + fact true "NixOS ${config.system.nixos.release}, `system.stateVersion = \"${config.system.stateVersion}\"` (never change it), kernel ${config.boot.kernelPackages.kernel.version}."
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
    in
    {
      ai.skills = {
        ai-tutor.source = "${self}/modules/skills/ai-tutor";
        nixos-system.source = nixosSystemSkill;
        # Skill dostarcza sam Brulion w pakiecie, razem z brulion-cli, który
        # opisuje, więc zawsze pasuje do wersji CLI w systemie. Ten sam pakiet
        # instaluje programs.brulion (desktop-brulion), więc nie dochodzi
        # żaden build.
        brulion = {
          source = "${brulionPackage}/share/brulion/agent-skills/brulion";
          packages = [ brulionPackage ];
        };
        obscura = {
          source = "${self}/modules/skills/obscura";
          packages = [ pkgs.obscura ];
        };
        # Skill pythonowy działa w kernelu IPython Prime Agenta.
        trilium-notes = {
          source = "${self}/modules/skills/trilium-notes";
          agents = [ "prime-agent" ];
          python = true;
        };
        # Część integracji claude-notify z hookami Claude Code; włącza ją
        # moduł claude-notify tam, gdzie wdrożył klucz (program skilla zależy
        # od hosta, więc pakiet powstaje tam, nie w packages).
        hermes-notify = {
          source = "${self}/modules/skills/hermes-notify";
          agents = [ "claude-code" ];
        };
      };

      ai.skillPacks = {
        qt-agent-skills.source = "${inputs.qt-agent-skills}/skills";
        tstack.source = "${inputs.tstack}/skills";
      };

      # Bez Trilium na hoście (customBot.triliumMcpUrl) skill nie ma serwera
      # MCP ani tokenu ETAPI.
      assertions = [
        {
          assertion = !config.ai.skills.trilium-notes.enable || config.customBot.triliumMcpUrl != null;
          message = "ai.skills.trilium-notes wymaga customBot.triliumMcpUrl (serwer MCP Trilium).";
        }
      ];
    };
}
