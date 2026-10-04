{ inputs, ... }:
{
  flake.modules.nixos.nixos-ai =
    { pkgs, ... }:
    {
      services = {
        ollama = {
          enable = true;
          # Wariant CUDA: wrapuje binarkę z LD_LIBRARY_PATH (runpath OpenGL),
          # więc ollama znajduje libcuda.so.1 sterownika NVIDIA i widzi dGPU.
          # Bez tego wykrywanie kończy się cicho na CPU (id=cpu w logu).
          package = pkgs.ollama-cuda;
        };
        open-webui = {
          enable = false;
          environment = {
            OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
            # Disable authentication
            WEBUI_AUTH = "False";
          };
        };
      };

      environment.systemPackages = with pkgs; [
        # uv pochodzi z base (sharedPackages) - nie duplikowac
        # OpenAI Codex CLI — agent kodujący w terminalu (nixpkgs)
        codex
        # Claude Code + przypięte pluginy i ich narzędzia
        # (modules/overlays/claude-code.nix)
        claude-code-bundle
        # ChatGPT — desktopowa aplikacja OpenAI (llm-agents.nix, deb x86_64)
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt
        repomix
        nodejs
        # skill: obscura — headless antidetect browser dla agentów (modules/skills/obscura)
        obscura
        # unsloth usunięty: torch z nixpkgs jest tu bez CUDA, a unsloth bez
        # akceleratora nie importuje się („You need a GPU”). Fine-tuning
        # trzymać w projekcie uv z kołami torch+CUDA.
        (python3.withPackages (python-pkgs: [ python-pkgs.pip ]))
      ];
    };
}
