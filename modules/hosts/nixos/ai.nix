{ inputs, ... }:
{
  flake.modules.nixos.nixos-ai =
    { pkgs, ... }:
    {
      services = {
        ollama = {
          enable = true;
          # package = pkgs.ollama; # domyślnie z nixpkgs, aktualizowany przez overlay ollama-latest
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
      ];
    };
}
