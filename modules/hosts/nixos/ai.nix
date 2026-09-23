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

      environment.sessionVariables = {
        # Skill trilium-notes (modules/skills/trilium-notes): na tym hoście działa
        # desktopowy Trilium (trilium-desktop w packages.nix, uruchamiany ręcznie,
        # ETAPI/MCP na 127.0.0.1:37840), a nie trilium-server:8081 z raspberry-pi-4
        # (default w skillu).
        TRILIUM_MCP_URL = "http://127.0.0.1:37840/mcp";
      };

      environment.systemPackages = with pkgs; [
        # uv pochodzi z base (sharedPackages) - nie duplikowac
        # OpenAI Codex CLI — agent kodujący w terminalu (llm-agents.nix)
        inputs.llm-agents.packages.${pkgs.system}.codex
        # ChatGPT — desktopowa aplikacja OpenAI (llm-agents.nix)
        inputs.llm-agents.packages.${pkgs.system}.chatgpt
        repomix
        nodejs
        # skill: obscura — headless antidetect browser dla agentów (modules/skills/obscura)
        obscura
        # python313 pinned: python3 (3.14) is too new for torchao, an unsloth dependency
        (pkgs.python313.withPackages (
          python-pkgs: with python-pkgs; [
            pip
            unsloth
          ]
        ))
      ];
    };
}
