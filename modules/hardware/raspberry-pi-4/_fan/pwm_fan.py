"""Wentylator PWM (Waveshare) na GPIO 14 według temperatury SoC.

Uruchamia go usługa pwm-fan (modules/hardware/raspberry-pi-4/fan.nix).
Gdy temperatury nie da się odczytać, wentylator kręci się na 100%:
brak odczytu nie może oznaczać wyłączonego chłodzenia.
"""

import sys
import time

import RPi.GPIO as GPIO

FAN_PIN = 14  # BCM 14 = fizyczny pin 8 (TXD)
PWM_HZ = 50
TEMP_FILE = "/sys/class/thermal/thermal_zone0/temp"
INTERVAL_S = 5


def duty_cycle(temp):
    """Wypełnienie PWM w procentach dla temperatury w °C (None: brak odczytu)."""
    if temp is None or temp >= 60.0:
        return 100
    if temp >= 48.0:
        return 50
    return 0


def read_temp():
    try:
        with open(TEMP_FILE) as f:
            return float(f.read()) / 1000.0
    except (OSError, ValueError):
        return None


def main():
    GPIO.setwarnings(False)
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(FAN_PIN, GPIO.OUT)
    pwm = GPIO.PWM(FAN_PIN, PWM_HZ)
    pwm.start(0)
    failing = False
    try:
        while True:
            temp = read_temp()
            if (temp is None) != failing:
                failing = temp is None
                state = "brak odczytu temperatury, 100%" if failing else "odczyt temperatury wrócił"
                print(f"pwm-fan: {state}", file=sys.stderr, flush=True)
            pwm.ChangeDutyCycle(duty_cycle(temp))
            time.sleep(INTERVAL_S)
    finally:
        pwm.stop()
        GPIO.cleanup()


if __name__ == "__main__":
    main()
