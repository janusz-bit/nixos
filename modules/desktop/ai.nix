# Narzędzia AI stacji roboczej: lokalna Ollama, agenty kodujące w terminalu
# (Codex, Claude Code, opencode, Antigravity), aplikacje desktopowe (ChatGPT,
# Hermes Desktop) i alias claude-nixos dla tego repo. Skille agentów:
# modules/skills/, klucze API wstrzykują wrappery fish (base/agenix.nix).
# Sprawdzenie: `systemctl status ollama`, `ollama ps` (kolumna PROCESSOR:
# GPU przy NVIDII).
{ inputs, customTop, ... }:
{
  flake.modules.nixos.desktop-ai =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      # Claude Code dla tego repo: zawsze w devShellu (nixfmt/deadnix/jq dla
      # hooków z .claude/, świeży hook pre-commit sync-github-actions).
      # `env -C` nie zmienia katalogu bieżącej powłoki; argumenty przechodzą
      # dalej (`claude-nixos --continue`).
      environment.shellAliases.claude-nixos = "env -C ${customTop.repository.place} nix develop -c claude";

      services = {
        ollama = {
          enable = true;
          # Z NVIDIĄ wariant CUDA: wrapuje binarkę z LD_LIBRARY_PATH (runpath
          # OpenGL), więc ollama znajduje libcuda.so.1 sterownika i widzi dGPU.
          # Bez tego wykrywanie kończy się cicho na CPU (id=cpu w logu).
          package = lib.mkIf config.hardware.nvidia.enabled pkgs.ollama-cuda;
        };
      };

      environment.systemPackages = with pkgs; [
        # uv pochodzi z base - nie duplikowac
        # OpenAI Codex CLI — agent kodujący w terminalu (nixpkgs)
        codex
        # Claude Code — agent kodujący w terminalu (nixpkgs)
        claude-code
        # ChatGPT — desktopowa aplikacja OpenAI (llm-agents.nix, deb x86_64;
        # chatgpt z nixpkgs jest tylko dla aarch64-darwin)
        inputs.llm-agents.packages.${system}.chatgpt
        repomix
        nodejs
        # unsloth usunięty: torch z nixpkgs jest tu bez CUDA, a unsloth bez
        # akceleratora nie importuje się („You need a GPU”). Fine-tuning
        # trzymać w projekcie uv z kołami torch+CUDA.
        (python3.withPackages (python-pkgs: [ python-pkgs.pip ]))
        # opencode z konfiguracją z overlaya (modules/overlays/opencode.nix)
        # opencode
        antigravity-ide-fhs
        antigravity-cli
        # Hermes Desktop (Electron) z flake hermes-agent; stan w ~/.hermes
        inputs.hermes-agent.packages.${system}.desktop
        inputs.llm-agents.packages.${system}.opencode2
        # Fork PrismML (formaty Bonsai); stockowy llama-cpp zostaje w drzewie
        # jako zależność whisper-cpp (kdenlive -> ffmpeg-full). Komentarz
        # i procedura aktualizacji: modules/packages/_llama-cpp-prism.
        (llama-cpp-prism.override { cudaSupport = true; })
        unsloth-desktop
      ];
    };
}
