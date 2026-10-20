# Serwer notatek Trilium na 127.0.0.1:8081, wystawiony tunelem jako
# notes.<domena>; jego MCP (/mcp, token ETAPI) czytają Hermes i prime-agent.
#
# Zmiana portu 8081 wymaga też cloudflared.nix, hermes.nix i domyślnego
# customBot.triliumMcpUrl.
#
# Sprawdzenie: `systemctl status trilium-server`.
_: {
  flake.modules.nixos.rpi-trilium = _: {
    services.trilium-server = {
      enable = true;
      port = 8081;
    };
  };
}
