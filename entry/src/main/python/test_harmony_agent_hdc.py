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

    def test_extract_json_payload_repairs_quoted_cjk_target_and_bare_bbox_with_extra_bracket(self):
        raw = (
            '{"reasoning":"select province","action":"click","parameters":'
            '{"target_element":"\u641c\u7d22\u7ed3\u679c\u4e2d\u7684"\u5e7f\u4e1c"\u9009\u9879",'
            '"bbox":132,280,1000,319]}}'
        )

        parsed = harmony_agent.extract_json_payload(raw)

        self.assertEqual("click", parsed["action"])
        self.assertIn("\u5e7f\u4e1c", parsed["parameters"]["target_element"])
        self.assertEqual([132, 280, 1000, 319], parsed["parameters"]["bbox"])

    def test_extract_json_payload_repairs_duplicate_colon_before_structured_bbox(self):
        raw = (
            '{"reasoning":"find Beijing","action":"click_input","parameters":'
            '{"target_element":"\u9876\u90e8\u652f\u6301\u641c\u7d22\u57ce\u5e02\uff0f\u56fd\u5bb6\u7684\u8f93\u5165\u6846",'
            '"text":"\u5317\u4eac","bbox"::[26,209,975,262]}}'
        )

        parsed = harmony_agent.extract_json_payload(raw)

        self.assertEqual("click_input", parsed["action"])
        self.assertEqual("\u5317\u4eac", parsed["parameters"]["text"])
        self.assertEqual([26, 209, 975, 262], parsed["parameters"]["bbox"])

    def test_decider_swipe_falls_back_to_direction_when_explicit_start_is_unsafe(self):
        original_driver = harmony_agent.d
        commands = []
        try:
            harmony_agent.d = None
            with patch.object(harmony_agent.time, "sleep", lambda _seconds: None), \
                    patch.object(harmony_agent, "hdc_prefix", lambda: "hdc"), \
                    patch.object(harmony_agent, "run_hdc_action_command",
                                 lambda _label, command: commands.append(command)):
                result = harmony_agent._execute_action_and_get_details_impl(json.dumps({
                    "action": "swipe",
                    "parameters": {
                        "direction": "DOWN",
                        "start_coords": [500, 200],
                        "end_coords": [500, 800],
                    },
                }), img_size=(1080, 2444))
        finally:
            harmony_agent.d = original_driver

        self.assertEqual(("swipe", {
            "direction": "DOWN",
            "start_coords": [500, 200],
            "end_coords": [500, 800],
        }), result)
        self.assertEqual(["hdc shell uitest uiInput swipe 540 733 540 1710"], commands)

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
