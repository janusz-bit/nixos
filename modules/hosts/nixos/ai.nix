{ ... }:
{
  flake.nixosModules."nixos/ai" =
    { pkgs, ... }:
    {
      services.ollama.enable = true;
      services.ollama.package = pkgs.ollama-cuda;
      services.open-webui = {
        enable = true;
        environment = {
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
          # Disable authentication
          WEBUI_AUTH = "False";
        };
      };

      environment.systemPackages = with pkgs; [
        uv
        repomix
      ];
    };
}
