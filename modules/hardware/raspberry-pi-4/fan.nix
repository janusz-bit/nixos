# Wentylator Waveshare PWM na GPIO 14 (BCM, fizyczny pin 8) Raspberry Pi 4:
# usługa pwm-fan steruje nim według temperatury SoC, a bez jej odczytu
# daje 100% (progi: _fan/pwm_fan.py).
#
# Biblioteka rpi-lgpio (zgodna z RPi.GPIO, działa przez /dev/gpiochip0):
# samo RPi.GPIO pada na nowszych kernelach (brak pola Hardware w
# /proc/cpuinfo), a usługa, która padła, zostawiała wentylator na 100%.
# /dev/gpiochip* to root:root 0600, więc usługa działa jako root, ale
# w piaskownicy: system plików tylko do odczytu, bez sieci i /home.
#
# Sprawdzenie: `systemctl status pwm-fan`, `journalctl -u pwm-fan -b`,
# temperatura: `cat /sys/class/thermal/thermal_zone0/temp` (m°C).
_: {
  flake.modules.nixos.hardware-raspberry-pi-4-fan =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (ps: [ ps.rpi-lgpio ]);
    in
    {
      systemd.services.pwm-fan = {
        description = "Waveshare PWM Fan Control";
        wantedBy = [ "multi-user.target" ];
        # rpi-lgpio nie wykrywa rewizji płytki: w device tree tego kernela
        # brakuje węzła system/ (temporary-fixes.md nr 7).
        environment.RPI_LGPIO_REVISION = "0xc03114"; # RPi4B Rev 1.4
        serviceConfig = {
          ExecStart = "${python.interpreter} ${./_fan/pwm_fan.py}";
          Restart = "always";
          RestartSec = "10";
          # lgpio tworzy w katalogu roboczym kolejki .lgd-nfy*; bez tego
          # lądowały w / (a przy ProtectSystem / jest tylko do odczytu).
          RuntimeDirectory = "pwm-fan";
          WorkingDirectory = "/run/pwm-fan";
          NoNewPrivileges = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          PrivateNetwork = true;
        };
      };
    };
}
