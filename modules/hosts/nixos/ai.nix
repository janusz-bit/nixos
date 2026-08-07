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
        (pkgs.python3.withPackages (
          python-pkgs: with python-pkgs; [
            pip
          ]
        ))
      ];
    };
}
