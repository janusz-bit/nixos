import os
import tempfile
import unittest

from pwm_fan import FULL, next_duty, read_temp


class NextDuty(unittest.TestCase):
    def test_unknown_temperature_is_full_speed(self):
        for current in (0, 50, 100):
            self.assertEqual(next_duty(None, current), FULL)

    def test_thresholds_from_rest(self):
        self.assertEqual(next_duty(40.0, 0), 0)
        self.assertEqual(next_duty(48.0, 0), 50)
        self.assertEqual(next_duty(59.9, 0), 50)
        self.assertEqual(next_duty(60.0, 0), 100)

    def test_hysteresis_holds_level_just_below_threshold(self):
        self.assertEqual(next_duty(47.5, 50), 50)
        self.assertEqual(next_duty(45.1, 50), 50)
        self.assertEqual(next_duty(45.0, 50), 0)
        self.assertEqual(next_duty(58.0, 100), 100)
        self.assertEqual(next_duty(57.0, 100), 50)

    def test_no_flapping_around_threshold(self):
        duty = 0
        seen = []
        for temp in (48.2, 47.9, 48.1, 47.8, 48.0, 47.6):
            duty = next_duty(temp, duty)
            seen.append(duty)
        self.assertEqual(seen, [50] * len(seen))


class ReadTemp(unittest.TestCase):
    def test_parses_millidegrees(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("48213\n")
        try:
            self.assertAlmostEqual(read_temp(f.name), 48.213)
        finally:
            os.unlink(f.name)

    def test_missing_or_garbage_sensor_is_none(self):
        self.assertIsNone(read_temp("/nonexistent/thermal"))
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("not-a-number")
        try:
            self.assertIsNone(read_temp(f.name))
        finally:
            os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
