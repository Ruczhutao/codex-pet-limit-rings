from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from PIL import ImageChops

from codex_pet_weather.atlas import ATLAS_HEIGHT, ATLAS_WIDTH, load_atlas, save_atlas, validate_atlas
from codex_pet_weather.cli import main
from codex_pet_weather.demo import make_demo_atlas
from codex_pet_weather.effects import weatherize_atlas
from codex_pet_weather.preview import make_contact_sheet
from codex_pet_weather.weather import manual_weather


class CoreTests(unittest.TestCase):
    def test_demo_atlas_has_codex_dimensions(self) -> None:
        image = make_demo_atlas()
        self.assertEqual(image.size, (ATLAS_WIDTH, ATLAS_HEIGHT))
        validate_atlas(image)

    def test_weatherize_changes_demo_atlas(self) -> None:
        base = make_demo_atlas()
        weather = manual_weather("storm", precipitation_mm=3, wind_speed_kmh=35, intensity=0.9)
        out = weatherize_atlas(base, weather, seed="test")
        diff = ImageChops.difference(base, out)
        self.assertIsNotNone(diff.getbbox())

    def test_save_and_load_webp(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            path = Path(td) / "atlas.webp"
            save_atlas(make_demo_atlas(), path)
            loaded = load_atlas(path)
            self.assertEqual(loaded.size, (ATLAS_WIDTH, ATLAS_HEIGHT))

    def test_contact_sheet_renders(self) -> None:
        sheet = make_contact_sheet(make_demo_atlas(), scale=0.25)
        self.assertGreater(sheet.width, 0)
        self.assertGreater(sheet.height, 0)

    def test_install_writes_pet_package(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            home = Path(td) / "codex-home"
            status = main(
                [
                    "install",
                    "--codex-home",
                    str(home),
                    "--pet-name",
                    "Test Weather",
                    "--condition",
                    "fog",
                    "--intensity",
                    "0.7",
                ]
            )
            self.assertEqual(status, 0)
            pet_dir = home / "pets" / "test-weather"
            self.assertTrue((pet_dir / "pet.json").exists())
            self.assertTrue((pet_dir / "spritesheet.webp").exists())
            self.assertTrue((pet_dir / "weather-state.json").exists())


if __name__ == "__main__":
    unittest.main()
