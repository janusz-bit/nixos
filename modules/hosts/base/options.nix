_: {
  flake.modules.nixos.base-options =
    { lib, ... }:
    {
      options.customBot = {
        # Bez wartości domyślnej: dawne "default" (= laptop) dawało hostowi,
        # który zapomniał tej opcji, aliasy wdrażające system laptopa.
        flakeTarget = lib.mkOption {
          type = lib.types.str;
          description = "Nazwa nixosConfigurations używana przez aliasy update/push; ustawia ją rejestr hostów (modules/hosts/registry.nix).";
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
