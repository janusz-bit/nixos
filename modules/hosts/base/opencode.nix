{ self, ... }:
{
  flake.nixosModules."base/opencode" =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.opencode ];

      environment.etc."opencode/opencode.json".source = self + /modules/configs/opencode/opencode.json;

      environment.etc."opencode/web-search-mcp.py".source =
        self + /modules/configs/opencode/web-search-mcp.py;

      systemd.tmpfiles.rules = [
        "L+ /home/${config.customBot.defaultUser}/.config/opencode/opencode.json - - - - /etc/opencode/opencode.json"
        "L+ /home/${config.customBot.defaultUser}/.config/opencode/web-search-mcp.py - - - - /etc/opencode/web-search-mcp.py"
      ];
    };
}
