{ self, ... }:
{
  flake.nixosModules."raspberry-pi-4/pwm-fan" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
        script =
          let
            pythonEnv = pkgs.python3.withPackages (ps: [ ps.rpi-gpio ]);
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
