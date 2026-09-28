_: {
  flake.modules.nixos.options =
    { lib, ... }:
    {
      options.customBot = {
        flakeTarget = lib.mkOption {
          type = lib.types.str;
          default = "default";
          description = "Nazwa nixosConfigurations używana przez aliasy update/push.";
        };
        enableFastfetch = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Czy fish_greeting ma uruchamiać fastfetch.";
        };
        defaultUser = lib.mkOption {
          type = lib.types.str;
          default = "nixos";
          description = "Główny użytkownik interaktywny hosta (właściciel sekretów użytkownika).";
        };
        triliumMcpUrl = lib.mkOption {
          type = lib.types.str;
          # trilium-server z raspberry-pi-4 (modules/hosts/raspberry-pi-4/trilium.nix)
          default = "http://127.0.0.1:8081/mcp";
          description = ''
            Endpoint MCP Trilium dla prime-agenta (settings.json) i skilla
            trilium-notes (TRILIUM_MCP_URL). Zależny od hosta: RPi ma
            trilium-server na 8081, laptop desktopowy Trilium na 37840.
          '';
        };
      };
    };
}
