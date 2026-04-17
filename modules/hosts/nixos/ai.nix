{ ... }:
{
  flake.nixosModules."nixos/ai" =
    { pkgs, ... }:
    {
      services.ollama.enable = true;
      services.ollama.package = pkgs.ollama-cuda;
      services.open-webui.enable = true;

      environment.systemPackages = with pkgs; [
        python3
        python3Packages.pip
        python3Packages.aiohttp
      ];
    };
}
