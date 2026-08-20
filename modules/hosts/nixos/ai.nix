{ inputs, ... }:
let
  pkgs-stable = import inputs.nixpkgs-stable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in
{
  flake.modules.nixos.nixos-ai =
    { pkgs, ... }:
    {
      services = {
        ollama = {
          enable = true;
          package = pkgs-stable.ollama; # temporary
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
        uv
        repomix
        nodejs
        # python313 pinned: python3 (3.14) is too new for torchao, an unsloth dependency
        (pkgs.python313.withPackages (
          python-pkgs: with python-pkgs; [
            pip
            unsloth
          ]
        ))
        # CUDA fine-tuning env: PyPI torch+CUDA wheel via uv (needs nix-ld, already in base).
        # Run once:  unsloth-cuda-setup
        # Then:      source ~/.venvs/unsloth-cuda/bin/activate
        (pkgs.writeShellScriptBin "unsloth-cuda-setup" ''
          set -euo pipefail
          VENV="$HOME/.venvs/unsloth-cuda"
          echo "Creating CUDA venv at $VENV ..."
          ${pkgs.uv}/bin/uv venv --python ${pkgs.python313}/bin/python3 "$VENV"
          # cu128 wheels = CUDA 12.8 (driver on this host supports 12.x)
          ${pkgs.uv}/bin/uv pip install --python "$VENV/bin/python" \
            torch --index-url https://download.pytorch.org/whl/cu128
          ${pkgs.uv}/bin/uv pip install --python "$VENV/bin/python" \
            unsloth unsloth-zoo
          echo
          echo "Done. Activate with:  source $VENV/bin/activate"
          echo "Check:               python -c 'import torch; print(torch.cuda.is_available())'"
        '')
      ];
    };
}
