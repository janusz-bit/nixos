_: {
  flake.modules.nixos.nixos-snapper =
    { config, pkgs, ... }:
    {
      services.snapper = {
        snapshotInterval = "hourly";
        cleanupInterval = "1d";
        configs = {
          root = {
            SUBVOLUME = "/";
            ALLOW_USERS = [ "${config.customBot.defaultUser}" ];
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 5;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 2;
            TIMELINE_LIMIT_MONTHLY = 0;
            TIMELINE_LIMIT_YEARLY = 0;
          };
          home = {
            SUBVOLUME = "/home";
            ALLOW_USERS = [ "${config.customBot.defaultUser}" ];
            TIMELINE_CREATE = true;
            TIMELINE_CLEANUP = true;
            TIMELINE_LIMIT_HOURLY = 10;
            TIMELINE_LIMIT_DAILY = 7;
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 3;
            TIMELINE_LIMIT_YEARLY = 0;
          };
        };
      };

      environment.systemPackages = with pkgs; [
        snapper
        snapper-gui
      ];
    };
}
