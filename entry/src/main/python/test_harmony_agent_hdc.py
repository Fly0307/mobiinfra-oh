import json
import unittest
from unittest.mock import patch

import harmony_agent


class FakeDriver:
    def __init__(self):
        self.events = []

    def click(self, x, y):
        self.events.append(("click", int(x), int(y)))

    def shell(self, command):
        self.events.append(("shell", command))

    def press_key(self, key):
        self.events.append(("press_key", key))

    def input_text(self, text):
        self.events.append(("input_text", text))


class HarmonyAgentHdcTest(unittest.TestCase):
    def test_refresh_forwarding_skips_hdc_command_when_target_missing(self):
        with patch.object(harmony_agent, "get_hdc_target", return_value=""), \
                patch.object(harmony_agent, "_refresh_hdc_forwarding_for_target") as run_fport, \
                patch.object(harmony_agent, "print_hdc_manual_config_hint") as print_hint:
            result = harmony_agent._refresh_hdc_forwarding_impl(verbose=True)

        self.assertEqual(result, 1)
        run_fport.assert_not_called()
        print_hint.assert_called_once_with(force=True)

    def test_decider_input_reactivates_previous_click_input_target(self):
        driver = FakeDriver()
        original_driver = harmony_agent.d
        try:
            harmony_agent.d = driver
            harmony_agent.clear_input_target()
            with patch.object(harmony_agent.time, "sleep", lambda _seconds: None):
                harmony_agent._execute_action_and_get_details_impl(json.dumps({
                    "action": "click_input",
                    "parameters": {
                        "coords": [100, 200],
                        "text": "小赵",
                    },
                }, ensure_ascii=False), img_size=(1000, 1000))
                result = harmony_agent._execute_action_and_get_details_impl(json.dumps({
                    "action": "input",
                    "parameters": {
                        "text": "华为mate80手机",
                    },
                }, ensure_ascii=False), img_size=(1000, 1000))
        finally:
            harmony_agent.d = original_driver
            harmony_agent.clear_input_target()

        self.assertEqual(("input", {"text": "华为mate80手机"}), result)
        self.assertEqual(2, driver.events.count(("click", 100, 200)))
        self.assertIn(("input_text", "华为mate80手机"), driver.events)

    def test_decider_input_without_known_target_is_rejected(self):
        driver = FakeDriver()
        original_driver = harmony_agent.d
        try:
            harmony_agent.d = driver
            harmony_agent.clear_input_target()
            with patch.object(harmony_agent.time, "sleep", lambda _seconds: None):
                with self.assertRaisesRegex(ValueError, "unknown focus"):
                    harmony_agent._execute_action_and_get_details_impl(json.dumps({
                        "action": "input",
                        "parameters": {
                            "text": "华为mate80手机",
                        },
                    }, ensure_ascii=False), img_size=(1000, 1000))
        finally:
            harmony_agent.d = original_driver
            harmony_agent.clear_input_target()

        self.assertNotIn(("input_text", "华为mate80手机"), driver.events)


if __name__ == "__main__":
    unittest.main()
