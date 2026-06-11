import json
import unittest
from datetime import datetime
from pathlib import Path

from wechat_collect.collector import (
    HistorySnapshotOptions,
    build_chat_payload,
    build_chat_payload_from_snapshots,
    compute_history_swipe,
    extract_chat_messages,
    extract_chat_title,
    extract_contacts,
    parse_chat_time,
    render_markdown,
)


ROOT = Path(__file__).resolve().parent / "wechat_collect" / "fixtures"


def load_fixture(name):
    with (ROOT / name).open("r", encoding="utf-8") as f:
        return json.load(f)


class WechatCollectParserTests(unittest.TestCase):
    def test_extracts_recent_contacts_from_home_dump(self):
        contacts = extract_contacts(load_fixture("home.json"))

        self.assertEqual([contact.name for contact in contacts], ["小赵", "项目群", "文件传输助手"])
        self.assertEqual(contacts[0].name, "小赵")
        self.assertEqual(contacts[0].last_time, "上午 10:45")
        self.assertEqual(contacts[0].preview, "需要给妹妹买一些少儿读物")
        self.assertEqual(contacts[0].tap_x, 628)
        self.assertEqual(contacts[0].tap_y, 589)

    def test_extracts_chat_title_and_messages(self):
        root = load_fixture("chat_xiao_zhao.json")

        self.assertEqual(extract_chat_title(root), "小赵")
        messages = extract_chat_messages(root)
        self.assertEqual(
            [(m.kind, m.sender, m.text) for m in messages],
            [
                ("time", None, "星期一 下午 03:47"),
                ("message", "self", "我想要买一个iPhone 17Pro"),
                ("message", "other", "需要给妹妹买一些少儿读物"),
            ],
        )

    def test_payload_uses_title_as_other_sender(self):
        payload = build_chat_payload(load_fixture("chat_xiao_zhao.json"))

        senders = [m["sender"] for m in payload["messages"] if m["kind"] == "message"]
        self.assertEqual(senders, ["self", "小赵"])
        self.assertNotIn("other", senders)

    def test_parses_wechat_time_labels(self):
        reference = datetime(2026, 6, 11, 12, 0)

        self.assertEqual(parse_chat_time("上午 10:45", reference), datetime(2026, 6, 11, 10, 45))
        self.assertEqual(parse_chat_time("昨天下午 07:39", reference), datetime(2026, 6, 10, 19, 39))
        self.assertEqual(parse_chat_time("星期一 下午 03:47", reference), datetime(2026, 6, 8, 15, 47))
        self.assertIsNone(parse_chat_time("以上是打招呼的内容", reference))
        for malformed in ["6月31号", "13/01 下午 01:00", "上午 25:00"]:
            with self.subTest(malformed=malformed):
                self.assertIsNone(parse_chat_time(malformed, reference))

    def test_snapshot_merge_deduplicates_boundary_overlap(self):
        payload = build_chat_payload_from_snapshots(
            [load_fixture("history_009.json"), load_fixture("history_010.json")],
            fallback_title="小赵",
            reference_now=datetime(2026, 6, 11, 12, 0),
        )
        texts = [message["text"] for message in payload["messages"]]

        self.assertEqual(
            texts,
            [
                "星期一 下午 02:00",
                "更早的一条消息",
                "边界重复消息",
                "星期一 下午 03:47",
                "我想要买一个iPhone 17Pro",
                "需要给妹妹买一些少儿读物",
            ],
        )
        self.assertEqual(texts.count("边界重复消息"), 1)

    def test_compute_history_swipe_uses_default_ratio(self):
        self.assertEqual(compute_history_swipe(load_fixture("chat_xiao_zhao.json")), (628, 483, 628, 2277))

    def test_render_markdown_includes_messages(self):
        chat_payload = build_chat_payload(load_fixture("chat_xiao_zhao.json"))
        payload = {
            "home_dump": "dumps/home.json",
            "conversations": [{
                "contact": {"name": "小赵"},
                "title": chat_payload["title"],
                "dump": "dumps/chat_01_小赵.json",
                "snapshots": ["dumps/chat_01_小赵.json"],
                "messages": chat_payload["messages"],
            }],
        }

        markdown = render_markdown(payload)

        self.assertIn("# 微信消息采集", markdown)
        self.assertIn("## 小赵", markdown)
        self.assertIn("- self: 我想要买一个iPhone 17Pro", markdown)
        self.assertIn("- 小赵: 需要给妹妹买一些少儿读物", markdown)

    def test_history_snapshot_options_are_service_friendly(self):
        options = HistorySnapshotOptions(days=7, hdc="custom-hdc")

        self.assertEqual(options.days, 7)
        self.assertEqual(options.hdc, "custom-hdc")
        self.assertEqual(options.max_history_swipes, 80)


if __name__ == "__main__":
    unittest.main()
