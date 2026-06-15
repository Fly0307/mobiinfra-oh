import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))

import hdc_server


class FakeDriver:
    def __init__(self):
        self.events = []

    def click(self, x, y):
        self.events.append(("click", x, y))

    def shell(self, command):
        self.events.append(("shell", command))

    def press_key(self, key):
        self.events.append(("press_key", key))

    def input_text(self, text):
        self.events.append(("input_text", text))


class FakeHarmonyAgent:
    DEVICE_WAIT_TIME = 0

    def __init__(self):
        self.d = FakeDriver()
        self.enter_pressed = False
        self.factor = None
        self.device_control_operations = []

    def run_driver_call(self, operation_name, operation):
        return operation(self.d)

    def run_with_device_control(self, operation_name, operation):
        self.device_control_operations.append(operation_name)
        return operation()

    def _capture_screen_mobiagent_style_impl(self, factor):
        self.factor = factor
        return "image-data", 540, 1170

    def press_harmony_key(self, name, fallback_code):
        self.enter_pressed = (name, fallback_code)


class WorkflowScreenshotTest(unittest.TestCase):
    def test_workflow_screenshot_does_not_manage_overlay_from_pc_socket(self):
        fake_agent = FakeHarmonyAgent()

        with patch.object(hdc_server, "harmony_agent", fake_agent), \
                patch.object(hdc_server, "is_hdc_connected", lambda force=False: True):
            result = hdc_server.handle_workflow_action("screenshot", {"factor": 0.5})

        self.assertEqual(result["status"], "ok")
        self.assertEqual(fake_agent.factor, 0.5)
        self.assertEqual(["workflow capture_screen_mobiagent direct"], fake_agent.device_control_operations)


class HdcServerWorkflowInputTest(unittest.TestCase):
    def test_click_input_uses_driver_text_input_when_driver_is_available(self):
        fake_agent = FakeHarmonyAgent()
        hdc_commands = []

        with patch.object(hdc_server, "harmony_agent", fake_agent), \
                patch.object(hdc_server, "run_hdc_command", lambda command: hdc_commands.append(command)), \
                patch.object(hdc_server, "hdc_prefix", lambda: "hdc -t fake"):
            result = hdc_server._workflow_gui_action_impl({
                "action": "click_input",
                "x": 100,
                "y": 200,
                "text": "小赵"
            })

        self.assertEqual("ok", result["status"])
        self.assertIn(("click", 100, 200), fake_agent.d.events)
        self.assertIn(("input_text", "小赵"), fake_agent.d.events)
        self.assertEqual(("ENTER", 2054), fake_agent.enter_pressed)
        self.assertEqual([], hdc_commands)


if __name__ == "__main__":
    unittest.main()
