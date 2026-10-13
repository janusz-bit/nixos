# Wentylator Waveshare PWM na GPIO 14 (BCM, fizyczny pin 8) Raspberry Pi 4:
# usługa pwm-fan co 5 s czyta temperaturę SoC (thermal_zone0) i ustawia
# wypełnienie 0% poniżej 48 °C, 50% od 48 °C i 100% od 60 °C.
#
# Biblioteka rpi-lgpio (zgodna z RPi.GPIO, działa przez /dev/gpiochip0):
# samo RPi.GPIO pada na nowszych kernelach (brak pola Hardware w
# /proc/cpuinfo), a usługa, która padła, zostawiała wentylator na 100%.
#
# Sprawdzenie: `systemctl status pwm-fan`, `journalctl -u pwm-fan -b`,
# temperatura: `cat /sys/class/thermal/thermal_zone0/temp` (m°C).
_: {
  flake.modules.nixos.hardware-raspberry-pi-4-fan =
    { pkgs, ... }:
    {
      systemd.services.pwm-fan = {
        description = "Waveshare PWM Fan Control";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "10";
          User = "root";
        };
        environment = {
          # rpi-lgpio can't detect RPi revision via /proc/device-tree on this kernel
          # (system/ node missing from DT). Provide it explicitly.
          RPI_LGPIO_REVISION = "0xc03114"; # RPi4B Rev 1.4
        };
        script =
          let
            pythonEnv = pkgs.python3.withPackages (ps: [ ps.rpi-lgpio ]);
          in
          ''
            ${pythonEnv}/bin/python -c '
            import RPi.GPIO as GPIO
            import time

            # GPIO 14 (BCM) odpowiada fizycznemu pinowi 8 (TXD) widocznemu na zdjęciu
            FAN_PIN = 14

            GPIO.setwarnings(False)
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(FAN_PIN, GPIO.OUT)
            pwm = GPIO.PWM(FAN_PIN, 50)
            pwm.start(0)

            def get_temp():
                try:
                    with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                        return float(f.read()) / 1000.0
                except:
                    return 0.0

            try:
                while True:
                    temp = get_temp()
                    if temp >= 60.0:
                        pwm.ChangeDutyCycle(100)
                    elif temp >= 48.0:
                        pwm.ChangeDutyCycle(50)
                    else:
                        pwm.ChangeDutyCycle(0)
                    time.sleep(5)
            except BaseException:
                pwm.stop()
                GPIO.cleanup()
            '
          '';
      };
    };
}
