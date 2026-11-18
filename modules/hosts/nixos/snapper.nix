# Snapper na laptopie: godzinowe snapshoty timeline podwolumenów btrfs / i
# /home (układ z disko.nix), sprzątane codziennie według limitów retencji;
# customBot.defaultUser obsługuje je z CLI bez roota (ALLOW_USERS), a GUI to
# btrfs-assistant (startuje przez pkexec, pyta o hasło).
#
# Sprawdzenie: `snapper -c root list`, `snapper -c home list`,
# `systemctl status snapper-timeline.timer snapper-cleanup.timer`.
_: {
  flake.modules.nixos.nixos-snapper =
    { config, pkgs, ... }:
    let
      user = config.users.users.${config.customBot.defaultUser};
      commonConfig = {
        ALLOW_USERS = [ config.customBot.defaultUser ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_YEARLY = 0;
      };
    in
    {
      # Snapper wymaga podwolumenu .snapshots w każdym snapshotowanym
      # podwolumenie (bez niego snapper-timeline pada co godzinę: „open failed
      # path:/home/.snapshots”); typ `v` tworzy podwolumen btrfs.
      #
      # Cache i worktree T3 (buildy C++/Qt po kilkadziesiąt GB, przebudowywane
      # wiele razy dziennie) to zagnieżdżone podwolumeny: snapshot /home ich
      # nie obejmuje, więc skasowane buildy nie zostają na dysku przez całą
      # retencję (w listopadzie 2026 snapshoty trzymały tak ~1,3 TB). `v` tworzy
      # podwolumen tylko gdy katalogu jeszcze nie ma; istniejący zwykły katalog
      # zostaje, trzeba go raz przenieść: `mv X X.old && btrfs subvolume create X
      # && cp -a --reflink=always X.old/. X/ && rm -rf X.old` (przy wyłączonych
      # programach, które go używają).
      systemd.tmpfiles.rules = [
        "v /.snapshots 0750 root root -"
        "v /home/.snapshots 0750 root root -"
        "v ${user.home}/.cache 0755 ${user.name} ${user.group} -"
        "d ${user.home}/.t3 0755 ${user.name} ${user.group} -"
        "v ${user.home}/.t3/worktrees 0755 ${user.name} ${user.group} -"
      ];

      services.snapper.configs = {
        root = commonConfig // {
          SUBVOLUME = "/";
          TIMELINE_LIMIT_HOURLY = 5;
          TIMELINE_LIMIT_WEEKLY = 2;
          TIMELINE_LIMIT_MONTHLY = 0;
        };
        home = commonConfig // {
          SUBVOLUME = "/home";
          TIMELINE_LIMIT_HOURLY = 10;
          TIMELINE_LIMIT_WEEKLY = 4;
          TIMELINE_LIMIT_MONTHLY = 3;
        };
      };

      # CLI snapper instaluje sam moduł services.snapper.
      # Nie snapper-gui: porzucony kod wymaga pkg_resources, którego nie ma już w
      # setuptools >= 82, więc pada przy starcie.
      environment.systemPackages = [ pkgs.btrfs-assistant ];
    };
}
