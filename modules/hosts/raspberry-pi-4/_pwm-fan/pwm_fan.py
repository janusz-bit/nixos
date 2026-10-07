"""Sterownik wentylatora PWM Waveshare na GPIO14 (fizyczny pin 8).

Logika (``next_duty``) jest czysta i testowana w ``test_pwm_fan.py``; ``main``
tylko czyta temperaturę i ustawia wypełnienie przez RPi.GPIO (rpi-lgpio).
"""

import signal
import sys
import time

# GPIO 14 (BCM) odpowiada fizycznemu pinowi 8 (TXD).
FAN_PIN = 14
PWM_FREQUENCY_HZ = 50
INTERVAL_S = 5
SENSOR = "/sys/class/thermal/thermal_zone0/temp"

# (próg włączenia w °C, wypełnienie w %) od najwyższego.
LEVELS = ((60.0, 100), (48.0, 50))
# Poziom spada dopiero HYSTERESIS_C poniżej progu, który go włączył — bez
# tego temperatura krążąca wokół progu przełączała wentylator co 5 s.
HYSTERESIS_C = 3.0
FULL = 100


def read_temp(path=SENSOR):
    """Temperatura w °C albo None, gdy czujnika nie da się odczytać."""
    try:
        with open(path) as f:
            return int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        return None


def next_duty(temp, current):
    """Wypełnienie dla odczytu ``temp`` przy obecnym wypełnieniu ``current``.

    Nieznana temperatura oznacza pełne obroty (bezpieczny kierunek awarii).
    """
    if temp is None:
        return FULL
    for threshold, duty in LEVELS:
        if temp >= threshold:
            return duty
        if current >= duty and temp > threshold - HYSTERESIS_C:
            return duty
    return 0


def main():
    import RPi.GPIO as GPIO

    def stop(_signum, _frame):
        sys.exit(0)

    # SIGTERM od systemd kończy pętlę przez finally (GPIO.cleanup), zamiast
    # zabijać interpreter bez sprzątania.
    signal.signal(signal.SIGTERM, stop)

    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(FAN_PIN, GPIO.OUT)
    pwm = GPIO.PWM(FAN_PIN, PWM_FREQUENCY_HZ)
    duty = FULL
    pwm.start(duty)
    sensor_ok = True
    try:
        while True:
            temp = read_temp()
            new = next_duty(temp, duty)
            if new != duty:
                pwm.ChangeDutyCycle(new)
                duty = new
            # Tylko przy zmianie stanu czujnika, nie co 5 s.
            if (temp is not None) != sensor_ok:
                sensor_ok = temp is not None
                if sensor_ok:
                    state = "readable again"
                else:
                    state = f"unreadable, fan at {FULL}%"
                print(f"pwm-fan: {SENSOR} {state}", file=sys.stderr)
            time.sleep(INTERVAL_S)
    finally:
        pwm.stop()
        GPIO.cleanup()


if __name__ == "__main__":
    main()
