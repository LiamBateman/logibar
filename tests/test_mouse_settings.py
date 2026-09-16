#!/usr/bin/env python3
import importlib.util
from importlib.machinery import SourceFileLoader
from pathlib import Path
import json
import tempfile
import unittest
from unittest.mock import patch

loader = SourceFileLoader("mouse_settings", str(Path(__file__).resolve().parent.parent / "logibar-mouse-settings"))
spec = importlib.util.spec_from_loader(loader.name, loader)
settings = importlib.util.module_from_spec(spec)
loader.exec_module(settings)
NAME = "logitech-g-pro-1"


class MouseSettingsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name)
        self.addCleanup(patch.stopall)
        patch.object(settings, "CONFIG", self.config).start()
        self.calls = []
        self.reject_reload = False
        self.reloaded = False
        self.mouse_connected = True
        patch.object(settings, "run", self.run_command).start()
        self.state, self.generated, self.main = settings.paths()
        self.main.parent.mkdir(parents=True)
        self.original = '-- Personal settings\nhl.config({ input = { sensitivity = 0.25 } })\n'
        self.main.write_text(self.original)

    def run_command(self, *args):
        self.calls.append(args)
        if args == ("hyprctl", "devices", "-j"):
            names = ["touchpad", "logitech-g915-tkl-1"] + ([NAME] if self.mouse_connected else [])
            return json.dumps({"mice": [{"name": n} for n in names]})
        if args == ("hyprctl", "reload"):
            self.reloaded = True
            return "ok"
        if args == ("hyprctl", "configerrors"):
            return "bad config" if self.reject_reload and self.reloaded else ""
        self.fail(f"Unexpected command: {args}")

    def test_discovery_excludes_keyboard_pointer_and_touchpad(self):
        self.assertEqual(settings.status(), {"devices": [{"name": NAME, "settings": None}]})
        self.assertFalse(self.state.exists())
        self.assertEqual(self.main.read_text(), self.original)

    def test_apply_preserves_user_config_and_persists_only_selected_mouse(self):
        result = settings.apply(NAME, -0.35, "flat")
        self.assertTrue(result["saved"])
        self.assertTrue(self.main.read_text().startswith(self.original))
        self.assertIn('sensitivity = -0.35, accel_profile = "flat"', self.generated.read_text())
        self.assertEqual(json.loads(self.state.read_text()), {NAME: {"sensitivity": -0.35, "accel_profile": "flat"}})
        self.assertEqual(self.main.with_name("hyprland.lua.before-logibar").read_text(), self.original)
        self.assertEqual(self.calls[-3:-1], [("hyprctl", "reload"), ("hyprctl", "configerrors")])

    def test_reapply_does_not_duplicate_include_or_erase_other_mice(self):
        settings.apply(NAME, -0.35, "flat")
        data = settings.read_settings()
        data["logitech-pro-x-superlight-1"] = {"sensitivity": 0.6, "accel_profile": "adaptive"}
        self.state.write_text(json.dumps(data))
        settings.apply(NAME, 0.1, "")
        self.assertEqual(self.main.read_text().count(settings.MARKER), 1)
        self.assertEqual(settings.read_settings()["logitech-pro-x-superlight-1"]["sensitivity"], 0.6)

    def test_invalid_values_and_injection_do_not_write_or_call_hyprland(self):
        for name, speed, profile in [(NAME, 1.1, "flat"), (NAME, float("nan"), "flat"),
                                     (NAME, float("inf"), "flat"), (NAME, 0, 'flat" })'),
                                     ('logitech-g-pro-1"; os.execute("x")', 0, "flat"),
                                     ("touchpad", 0, "flat")]:
            with self.subTest(name=name, speed=speed, profile=profile):
                with self.assertRaises(ValueError):
                    settings.apply(name, speed, profile)
        self.assertEqual(self.calls, [])
        self.assertFalse(self.generated.exists())

    def test_disconnected_mouse_cannot_be_changed(self):
        self.mouse_connected = False
        with self.assertRaisesRegex(ValueError, "disconnected"):
            settings.apply(NAME, 0.4, "flat")
        self.assertFalse(self.generated.exists())

    def test_failed_reload_rolls_back_new_include_and_files(self):
        self.reject_reload = True
        with self.assertRaisesRegex(ValueError, "rejected"):
            settings.apply(NAME, -0.5, "adaptive")
        self.assertEqual(self.main.read_text(), self.original)
        self.assertFalse(self.generated.exists())
        self.assertFalse(self.state.exists())
        self.assertEqual(self.calls.count(("hyprctl", "reload")), 2)

    def test_failed_update_restores_previous_saved_values(self):
        settings.apply(NAME, -0.5, "flat")
        previous = {p: p.read_text() for p in settings.paths()}
        self.reloaded = False
        self.reject_reload = True
        with self.assertRaises(ValueError):
            settings.apply(NAME, 0.4, "adaptive")
        self.assertEqual({p: p.read_text() for p in settings.paths()}, previous)


if __name__ == "__main__":
    unittest.main()
