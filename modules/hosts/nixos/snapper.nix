# Snapper na laptopie: godzinowe snapshoty timeline podwolumenów btrfs / i
# /home (układ z disko.nix), sprzątane codziennie według limitów retencji;
# customBot.defaultUser obsługuje je z CLI bez roota (ALLOW_USERS), a GUI to
# btrfs-assistant (startuje przez pkexec, pyta o hasło). ~/.cache i
# ~/.t3/worktrees są osobnymi podwolumenami poza snapshotami (usługa
# home-subvolumes zamienia je przy starcie).
#
# Sprawdzenie: `snapper -c root list`, `snapper -c home list`,
# `systemctl status snapper-timeline.timer snapper-cleanup.timer`.
_: {
  flake.modules.nixos.nixos-snapper =
    {
      config,
      lib,
      pkgs,
      utils,
      ...
    }:
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
      systemd.tmpfiles.rules = [
        "v /.snapshots 0750 root root -"
        "v /home/.snapshots 0750 root root -"
      ];

      # Cache i worktree T3 (buildy C++/Qt po kilkadziesiąt GB, przebudowywane
      # wiele razy dziennie) to zagnieżdżone podwolumeny: snapshot /home ich
      # nie obejmuje, więc skasowane buildy nie zostają na dysku przez całą
      # retencję (w listopadzie 2026 snapshoty trzymały tak ~1,3 TB). Typ `v`
      # tmpfiles nie zamienia istniejącego katalogu, więc robi to ta usługa:
      # przy starcie, przed logowaniem (nic wtedy z nich nie korzysta), jako
      # właściciel, bez roota. Po migracji to tylko `stat`.
      # Rootless podman zostawia w ~/.cache pliki subuidów (brulion-fdroid),
      # których zwykły użytkownik nie skopiuje z właścicielem ani nie usunie,
      # dlatego skrypt działa w przestrzeni nazw użytkownika z mapą subuid
      # (`unshare --map-auto` przez setuidowy newuidmap: stąd /run/wrappers w
      # PATH i brak NoNewPrivileges).
      # Sprawdzenie: `systemctl status home-subvolumes`, `stat -c %i ~/.cache`
      # (256 = podwolumen).
      systemd.services.home-subvolumes = {
        description = "Podwolumeny btrfs poza snapshotami /home";
        wantedBy = [ "multi-user.target" ];
        before = [ "systemd-user-sessions.service" ];
        unitConfig.RequiresMountsFor = [ user.home ];
        path = [ (dirOf config.security.wrapperDir) ];
        serviceConfig = {
          Type = "oneshot";
          User = user.name;
          Group = user.group;
          # switch-to-configuration startuje nowe usługi od razu, w trakcie
          # sesji; z działającym `systemd --user` migracja czeka na restart.
          ExecCondition = utils.escapeSystemdExecArgs [
            (lib.getExe (
              pkgs.writeShellApplication {
                name = "home-subvolumes-no-session";
                runtimeInputs = [ pkgs.procps ];
                text = ''
                  status=0
                  pgrep -u "$1" -x systemd >/dev/null || status=$?
                  if [ "$status" -ne 1 ]; then
                    echo "$1 ma aktywną sesję; migracja przy następnym starcie"
                    exit 1
                  fi
                '';
              }
            ))
            user.name
          ];
          ExecStart = utils.escapeSystemdExecArgs [
            (lib.getExe' pkgs.util-linux "unshare")
            "--map-auto"
            "--map-root-user"
            (lib.getExe (
              pkgs.writeShellApplication {
                name = "home-subvolumes";
                runtimeInputs = with pkgs; [
                  btrfs-progs
                  coreutils
                ];
                text = builtins.readFile ./_snapper/home-subvolumes.sh;
              }
            ))
            "${user.home}/.cache"
            "${user.home}/.t3/worktrees"
          ];
          # Jednorazowa kopia reflinkami setek GB trwa dłużej niż domyślne 90 s.
          TimeoutStartSec = "infinity";
          ProtectSystem = "strict";
          ReadWritePaths = [ user.home ];
          PrivateTmp = true;
        };
      };

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
