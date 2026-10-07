_: {
  flake.modules.nixos.pwm-fan =
    { pkgs, ... }:
    let
      # Logika w _pwm-fan/pwm_fan.py (testy: checks.<system>.pwm-fan).
      pwmFan = pkgs.writers.writePython3 "pwm-fan" {
        libraries = [ pkgs.python3Packages.rpi-lgpio ];
      } (builtins.readFile ./_pwm-fan/pwm_fan.py);
    in
    {
      systemd.services.pwm-fan = {
        description = "Waveshare PWM Fan Control";
        wantedBy = [ "multi-user.target" ];
        environment = {
          # rpi-lgpio can't detect RPi revision via /proc/device-tree on this kernel
          # (system/ node missing from DT). Provide it explicitly.
          RPI_LGPIO_REVISION = "0xc03114"; # RPi4B Rev 1.4
          # lgpio zakłada w katalogu roboczym FIFO powiadomień (.lgd-nfy*) —
          # wcześniej lądowało w /.
          LG_WD = "/run/pwm-fan";
        };
        serviceConfig = {
          ExecStart = pwmFan;
          Restart = "always";
          # Po wyjściu procesu pin wraca do wejścia (wentylator stoi) — wznowić
          # sterowanie od razu.
          RestartSec = "2s";
          RuntimeDirectory = "pwm-fan";
          WorkingDirectory = "/run/pwm-fan";
          # /dev/gpiochip0 to root:root 0600, a reguła udev dla innej grupy
          # zadziałałaby dopiero po ponownym starcie (switch nie wyzwala
          # urządzeń), zatrzymując wentylator. Dlatego uid 0, ale bez żadnych
          # capabilities: dostęp wynika z właściciela pliku, a system plików,
          # sieć i reszta urządzeń są dla usługi niedostępne.
          User = "root";
          CapabilityBoundingSet = "";
          NoNewPrivileges = true;
          DevicePolicy = "closed";
          DeviceAllow = [ "/dev/gpiochip0 rw" ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
          IPAddressDeny = "any";
          RestrictAddressFamilies = [ "AF_UNIX" ];
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          ProtectClock = true;
          ProtectHostname = true;
          ProtectProc = "invisible";
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
          ];
          SystemCallErrorNumber = "EPERM";
          UMask = "0077";
        };
      };
    };
}
