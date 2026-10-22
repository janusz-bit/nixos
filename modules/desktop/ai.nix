# Narzędzia AI stacji roboczej: lokalna Ollama i llama.cpp, agenty kodujące
# (Codex, Claude Code, opencode, Antigravity), ChatGPT i Hermes Desktop oraz
# alias claude-nixos. Klucze API wstrzykują wrappery fish (base/agenix.nix).
# Sprawdzenie: `ollama ps` (kolumna PROCESSOR: GPU przy NVIDII).
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
      # Zawsze w devShellu: hooki z .claude/ i pre-commit potrzebują jego narzędzi.
      # `env -C` nie zmienia katalogu bieżącej powłoki; argumenty przechodzą
      # dalej (`claude-nixos --continue`).
      environment.shellAliases.claude-nixos = "env -C ${customTop.repository.place} nix develop -c claude";

      services.ollama = {
        enable = true;
        # Wariant CUDA dodaje katalog sterownika (runpath OpenGL) do LD_LIBRARY_PATH,
        # więc ollama znajduje libcuda.so.1; bez niego wykrywanie GPU kończy się
        # cicho na CPU (id=cpu w logu).
        package = lib.mkIf config.hardware.nvidia.enabled pkgs.ollama-cuda;
      };

      environment.systemPackages = with pkgs; [
        # uv jest w base (hosts/base/configuration.nix).
        codex
        claude-code
        # chatgpt z nixpkgs jest tylko na aarch64-darwin; llm-agents ma deb x86_64.
        inputs.llm-agents.packages.${system}.chatgpt
        repomix
        nodejs
        # Bez pythonowego unsloth: torch z nixpkgs nie ma tu CUDA, a unsloth bez GPU
        # się nie importuje. Fine-tuning w projekcie uv z kołami torch+CUDA.
        (python3.withPackages (python-pkgs: [ python-pkgs.pip ]))
        antigravity-ide-fhs
        antigravity-cli
        inputs.hermes-agent.packages.${system}.desktop
        inputs.llm-agents.packages.${system}.opencode2
        # Fork PrismML (Bonsai) ma te same nazwy binarek, więc nie jest w PATH,
        # tylko pod aliasem llama-prism (skills/external.nix).
        (llama-cpp.override { cudaSupport = config.hardware.nvidia.enabled; })
        unsloth-desktop
      ];
    };
}
