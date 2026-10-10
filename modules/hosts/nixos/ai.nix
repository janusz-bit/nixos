{ inputs, customTop, ... }:
{
  flake.modules.nixos.nixos-ai =
    { pkgs, ... }:
    {
      # Claude Code dla tego repo: zawsze w devShellu (nixfmt/deadnix/jq dla
      # hooków z .claude/, świeży hook pre-commit sync-github-actions).
      # `env -C` nie zmienia katalogu bieżącej powłoki; argumenty przechodzą
      # dalej (`claude-nixos --continue`).
      environment.shellAliases.claude-nixos = "env -C ${customTop.repository.place} nix develop -c claude";

      services = {
        ollama = {
          enable = true;
          # Wariant CUDA: wrapuje binarkę z LD_LIBRARY_PATH (runpath OpenGL),
          # więc ollama znajduje libcuda.so.1 sterownika NVIDIA i widzi dGPU.
          # Bez tego wykrywanie kończy się cicho na CPU (id=cpu w logu).
          package = pkgs.ollama-cuda;
        };
      };

      environment.systemPackages = with pkgs; [
        # uv pochodzi z base (sharedPackages) - nie duplikowac
        # OpenAI Codex CLI — agent kodujący w terminalu (nixpkgs)
        codex
        # Claude Code — agent kodujący w terminalu (nixpkgs)
        claude-code
        # ChatGPT — desktopowa aplikacja OpenAI (llm-agents.nix, deb x86_64)
        inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.chatgpt
        repomix
        nodejs
        # unsloth usunięty: torch z nixpkgs jest tu bez CUDA, a unsloth bez
        # akceleratora nie importuje się („You need a GPU”). Fine-tuning
        # trzymać w projekcie uv z kołami torch+CUDA.
        (python3.withPackages (python-pkgs: [ python-pkgs.pip ]))
      ];
    };
}
