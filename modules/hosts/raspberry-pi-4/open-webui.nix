{ ... }:
{
  flake.nixosModules."raspberry-pi-4/open-webui" =
    { pkgs, ... }:
    {
      services.open-webui = {
        enable = true;
        host = "127.0.0.1";
        port = 8080;
        environment = {
          OLLAMA_API_BASE_URL = "http://127.0.0.1:11434";
          WEBUI_AUTH = "False";
        };
      };
    };
}
