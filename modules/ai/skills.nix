# Katalog skilli agentów AI: które skille repozytorium zna (ai.skills) i skąd
# pochodzą paczki skilli z wejść flake'a (ai.skillPacks; Qt Development Skills
# z wejścia qt-agent-skills, tstack, czyli prowadzenie PR przez review i CI
# do merge'a przez gh, i frontend-design z oficjalnego marketplace'u pluginów
# Claude Code). Same skille leżą w modules/skills/<nazwa>/ (SKILL.md +
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
          fact (config.customBot.tailscaleServe != { })
            "Server: web services listen on localhost and are published only to the tailnet through Tailscale Serve (`customBot.tailscaleServe`: tailnet HTTPS port -> 127.0.0.1 port, `tailscale serve status`); sshd accepts the home LAN and `tailscale0`."
        + fact pkgs.stdenv.hostPlatform.isAarch64 "Low-power ARM board (`nix.settings.max-jobs = ${toString config.nix.settings.max-jobs}`): avoid local builds and heavy evaluations here.";
    in
    {
      ai.skills = {
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
        # Skill z pakietu rea-agents, razem z CLI `rea`, które opisuje, więc
        # zawsze pasuje do jego wersji. Serwera MCP nie rejestruje (`rea setup
        # --client <agent>`).
        reverse-engineer-anything = {
          source = "${pkgs.rea-agents}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";
          packages = [ pkgs.rea-agents ];
        };
        # Czyta token OAuth Claude Code (~/.claude/.credentials.json), więc ma
        # sens tylko na koncie zalogowanym do subskrypcji Claude; inni agenci
        # też mogą go wołać, bo limity są wspólne dla całego konta.
        claude-usage = {
          source = "${self}/modules/skills/claude-usage";
          packages = [
            (pkgs.writeShellApplication {
              name = "claude-usage";
              runtimeInputs = with pkgs; [
                curl
                jq
              ];
              text = builtins.readFile ./_claude-usage/claude-usage.sh;
            })
          ];
        };
        # Skill pythonowy działa w kernelu IPython Prime Agenta.
        trilium-notes = {
          source = "${self}/modules/skills/trilium-notes";
          agents = [ "prime-agent" ];
          python = true;
        };
      };

      ai.skillPacks = {
        qt-agent-skills.source = "${inputs.qt-agent-skills}/skills";
        tstack.source = "${inputs.tstack}/skills";
        frontend-design.source = "${inputs.claude-plugins-official}/plugins/frontend-design/skills";
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
