import unittest

import hdc_server


class FakeHarmonyAgent:
    def __init__(self):
        self.factor = None
        self.manage_overlay = None

    def capture_screen_mobiagent_style(self, factor, manage_overlay):
        self.factor = factor
        self.manage_overlay = manage_overlay
        return "image-data", 540, 1170


class WorkflowScreenshotTest(unittest.TestCase):
    def test_workflow_screenshot_does_not_manage_overlay_from_pc_socket(self):
        original_agent = hdc_server.harmony_agent
        original_is_connected = hdc_server.is_hdc_connected
        fake_agent = FakeHarmonyAgent()
        try:
            hdc_server.harmony_agent = fake_agent
            hdc_server.is_hdc_connected = lambda force=False: True

            result = hdc_server.handle_workflow_action("screenshot", {"factor": 0.5})

            self.assertEqual(result["status"], "ok")
            self.assertEqual(fake_agent.factor, 0.5)
            self.assertFalse(fake_agent.manage_overlay)
        finally:
            hdc_server.harmony_agent = original_agent
            hdc_server.is_hdc_connected = original_is_connected


if __name__ == "__main__":
    unittest.main()
