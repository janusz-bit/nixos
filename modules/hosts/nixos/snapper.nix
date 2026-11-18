# Snapper na laptopie: dzienne snapshoty timeline podwolumenów btrfs / i
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
      commonConfig = {
        ALLOW_USERS = [ config.customBot.defaultUser ];
        TIMELINE_CREATE = true;
        TIMELINE_CLEANUP = true;
        TIMELINE_LIMIT_HOURLY = 0;
        TIMELINE_LIMIT_DAILY = 7;
        TIMELINE_LIMIT_YEARLY = 0;
      };
    in
    {
      # Snapper wymaga podwolumenu .snapshots w każdym snapshotowanym
      # podwolumenie (bez niego każdy snapper-timeline pada: „open failed
      # path:/home/.snapshots”); typ `v` tworzy podwolumen btrfs.
      systemd.tmpfiles.rules = [
        "v /.snapshots 0750 root root -"
        "v /home/.snapshots 0750 root root -"
      ];

      # Raz dziennie zamiast co godzinę: buildy w /home (kilkadziesiąt GB,
      # przebudowywane wiele razy dziennie) trafiały do kilku snapshotów na
      # dobę i trzymały miejsce przez całą retencję (w listopadzie 2026 ~1,3 TB).
      # persistentTimer: snapshot dnia pominięty przy wyłączonym laptopie
      # (OnCalendar=daily to północ) robi się po włączeniu.
      services.snapper = {
        snapshotInterval = "daily";
        persistentTimer = true;

        configs = {
          root = commonConfig // {
            SUBVOLUME = "/";
            TIMELINE_LIMIT_WEEKLY = 2;
            TIMELINE_LIMIT_MONTHLY = 0;
          };
          home = commonConfig // {
            SUBVOLUME = "/home";
            TIMELINE_LIMIT_WEEKLY = 4;
            TIMELINE_LIMIT_MONTHLY = 3;
          };
        };
      };

      # CLI snapper instaluje sam moduł services.snapper.
      # Nie snapper-gui: porzucony kod wymaga pkg_resources, którego nie ma już w
      # setuptools >= 82, więc pada przy starcie.
      environment.systemPackages = [ pkgs.btrfs-assistant ];
    };
}
