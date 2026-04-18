{ ... }:
{
  flake.nixosModules."nixos/ai" =
    { pkgs, ... }:
    {
      services.ollama.enable = true;
      services.ollama.package = pkgs.ollama-cuda;
      # services.open-webui.enable = true;

      environment.systemPackages = with pkgs; [
        uv
        repomix
      ];
    };
}
