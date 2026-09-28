_: {
  flake.modules.nixos.nixos-snapper =
    { config, pkgs, ... }:
    let
      allowUsers = [ config.customBot.defaultUser ];
    in
    {
      # Snapper wymaga podwolumenu .snapshots w każdym snapshotowanym
      # podwolumenie — bez niego snapper-timeline pada co godzinę
      # („open failed path:/home/.snapshots”). Typ `v` tworzy podwolumen btrfs.
      #
      # Duże, szybko zmieniające się katalogi (Steam, ~/.cache, modele,
      # obrazy kontenerów) trzymaj w osobnych podwolumenach — zagnieżdżony
      # podwolumen nie wchodzi do snapshotu rodzica.
      systemd.tmpfiles.rules = [
        "v /.snapshots 0750 root root -"
        "v /home/.snapshots 0750 root root -"
      ];

      services.snapper = {
        snapshotInterval = "hourly";
        cleanupInterval = "1d";
        configs = {
          root = {
            SUBVOLUME = "/";
            ALLOW_USERS = allowUsers;
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
            ALLOW_USERS = allowUsers;
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
