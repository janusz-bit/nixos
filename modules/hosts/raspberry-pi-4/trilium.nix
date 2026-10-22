# Serwer notatek Trilium na 127.0.0.1:8081, wystawiony tunelem jako
# notes.<domena>; jego MCP (/mcp, token ETAPI) czytają Hermes i prime-agent.
#
# cloudflared.nix i hermes.nix czytają services.trilium-server.port. Port
# 8081 powtarzają jeszcze: domyślny customBot.triliumMcpUrl i jego opis
# (base/options.nix), skill trilium-notes (_DEFAULT_URL i SKILL.md) oraz mapa
# w nagłówku cloudflared.nix.
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
