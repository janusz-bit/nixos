{ ... }:
{
  flake.nixosModules."nixos/ai" =
    { pkgs, ... }:
    {
      services.ollama.enable = true;
      services.ollama.package = pkgs.ollama-cuda;
      services.open-webui = {
        enable = true;
        environment = "{\n  OLLAMA_API_BASE_URL = \"http://127.0.0.1:11434\";\n  # Disable authentication\n  WEBUI_AUTH = \"False\";\n}\n";
      };

      environment.systemPackages = with pkgs; [
        uv
        repomix
      ];
    };
}
