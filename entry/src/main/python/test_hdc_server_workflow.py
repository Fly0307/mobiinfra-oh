import unittest

import hdc_server


class FakeHarmonyAgent:
    def __init__(self):
        self.factor = None
        self.manage_overlay = None

    def run_with_device_control(self, label, fn):
        return fn()

    def capture_screen_mobiagent_style(self, factor, manage_overlay):
        self.factor = factor
        self.manage_overlay = manage_overlay
        return "image-data", 540, 1170

    def _capture_screen_mobiagent_style_impl(self, factor):
        return self.capture_screen_mobiagent_style(factor, False)

    def hdc_prefix(self):
        return "hdc"

    def run_gui_task(self, task):
        return {"status": "ok", "task": task}


class FakeWechatCollectService:
    def __init__(self):
        self.uidump_payload = None
        self.collect_payload = None

    def uidump_action(self, payload, hdc_prefix):
        self.uidump_payload = payload
        return {
            "status": "ok",
            "message": "uidump ok",
            "dump_path": "/tmp/ui_tree.json",
            "ui_tree": {},
        }

    def collect_action(self, payload, hdc_prefix, gui_search):
        self.collect_payload = payload
        return {
            "status": "ok",
            "message": "wechat_collect service skeleton ready",
            "run_id": "20260611T120000-wechat",
            "conversations": [],
        }


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


class WechatWorkflowBridgeTest(unittest.TestCase):
    def test_uidump_delegates_to_wechat_service(self):
        original_agent = hdc_server.harmony_agent
        original_service = hdc_server.wechat_collect_service
        original_is_connected = hdc_server.is_hdc_connected
        fake_service = FakeWechatCollectService()
        try:
            hdc_server.harmony_agent = FakeHarmonyAgent()
            hdc_server.wechat_collect_service = fake_service
            hdc_server.is_hdc_connected = lambda force=False: True

            result = hdc_server.handle_workflow_action("uidump", {
                "remote_path": "/data/local/tmp/ui_tree.json",
            })

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["message"], "uidump ok")
            self.assertEqual(fake_service.uidump_payload, {
                "remote_path": "/data/local/tmp/ui_tree.json",
            })
        finally:
            hdc_server.harmony_agent = original_agent
            hdc_server.wechat_collect_service = original_service
            hdc_server.is_hdc_connected = original_is_connected

    def test_wechat_collect_delegates_to_wechat_service(self):
        original_agent = hdc_server.harmony_agent
        original_service = hdc_server.wechat_collect_service
        original_is_connected = hdc_server.is_hdc_connected
        fake_service = FakeWechatCollectService()
        try:
            hdc_server.harmony_agent = FakeHarmonyAgent()
            hdc_server.wechat_collect_service = fake_service
            hdc_server.is_hdc_connected = lambda force=False: True

            result = hdc_server.handle_workflow_action("wechat_collect", {
                "mode": "recent_contacts",
                "days": 7,
                "max_contacts": 10,
            })

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["run_id"], "20260611T120000-wechat")
            self.assertEqual(fake_service.collect_payload["max_contacts"], 10)
        finally:
            hdc_server.harmony_agent = original_agent
            hdc_server.wechat_collect_service = original_service
            hdc_server.is_hdc_connected = original_is_connected


if __name__ == "__main__":
    unittest.main()
