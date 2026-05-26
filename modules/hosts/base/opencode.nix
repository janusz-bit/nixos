{ self, ... }:
{
  flake.nixosModules."base/opencode" =
    { config, pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.opencode ];

      environment.etc."opencode/opencode.json".source = self + /modules/configs/opencode/opencode.json;

      systemd.tmpfiles.rules = [
        "L+ /home/${config.custom.defaultUser}/.config/opencode/opencode.json - - - - /etc/opencode/opencode.json"
      ];
    };
}
