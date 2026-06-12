import json
import subprocess
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch

from wechat_collect.collector import (
    CollectOptions,
    Contact,
    DEFAULT_HISTORY_SWIPE_RATIO,
    DEFAULT_SWIPE_SPEED,
    HistorySnapshotOptions,
    build_chat_payload,
    build_chat_payload_from_snapshots,
    collect_visible_chats,
    compute_history_swipe,
    extract_chat_messages,
    extract_chat_title,
    extract_contacts,
    parse_chat_time,
    render_markdown,
)
from wechat_collect import (
    collect_recent_contacts_from_dumps,
    daily_log_entries_from_conversations,
    normalize_collect_request,
)
from wechat_collect import service as wechat_collect_service


ROOT = Path(__file__).resolve().parent / "wechat_collect" / "fixtures"


def load_fixture(name):
    with (ROOT / name).open("r", encoding="utf-8") as f:
        return json.load(f)


def ui_node(node_type, text="", bounds="[0,0][100,100]", children=None):
    attrs = {
        "type": node_type,
        "bounds": bounds,
        "origBounds": bounds,
    }
    if text:
        attrs["text"] = text
    return {
        "attributes": attrs,
        "children": children or [],
    }


def search_home_root():
    return ui_node("Root", bounds="[0,0][1256,2760]", children=[
        ui_node("Text", text="搜索", bounds="[180,130][1060,220]"),
    ])


def search_results_root():
    return ui_node("Root", bounds="[0,0][1256,2760]", children=[
        ui_node("List", bounds="[0,260][1256,2600]", children=[
            ui_node("ListItem", bounds="[0,300][1256,520]", children=[
                ui_node("Text", text="最常使用", bounds="[70,305][280,345]"),
                ui_node("Text", text="小赵", bounds="[210,330][520,390]"),
                ui_node("Text", text="微信号: xiao-zhao", bounds="[210,400][720,460]"),
            ]),
        ]),
    ])


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
        self.assertEqual(compute_history_swipe(load_fixture("chat_xiao_zhao.json")), (628, 828, 628, 1932))

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

    def test_collect_visible_chats_validates_before_tapping_device(self):
        calls = []
        contact = Contact(
            name="小赵",
            last_time="上午 10:45",
            preview="",
            bounds=(0, 500, 1256, 678),
            tap_x=628,
            tap_y=589,
            raw_texts=["小赵"],
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("wechat_collect.device.dump_layout", return_value=Path(temp_dir) / "home.json"), \
                    patch("wechat_collect.device.load_ui_tree", return_value={}), \
                    patch("wechat_collect.device.extract_contacts", return_value=[contact]), \
                    patch("wechat_collect.device.tap", side_effect=lambda *args, **kwargs: calls.append("tap")):
                with self.assertRaises(ValueError):
                    collect_visible_chats(CollectOptions(dump_dir=temp_dir, days=-1, wait=0))

        self.assertEqual(calls, [])

    def test_collect_visible_chats_returns_from_chat_when_collection_fails(self):
        calls = []
        contact = Contact(
            name="小赵",
            last_time="上午 10:45",
            preview="",
            bounds=(0, 500, 1256, 678),
            tap_x=628,
            tap_y=589,
            raw_texts=["小赵"],
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("wechat_collect.device.dump_layout", return_value=Path(temp_dir) / "page.json"), \
                    patch("wechat_collect.device.load_ui_tree", return_value={}), \
                    patch("wechat_collect.device.extract_contacts", return_value=[contact]), \
                    patch("wechat_collect.device.tap", side_effect=lambda *args, **kwargs: calls.append("tap")), \
                    patch("wechat_collect.device.press_back", side_effect=lambda *args, **kwargs: calls.append("back")), \
                    patch("wechat_collect.device.build_chat_payload", side_effect=RuntimeError("bad dump")):
                with self.assertRaises(RuntimeError):
                    collect_visible_chats(CollectOptions(dump_dir=temp_dir, wait=0))

        self.assertEqual(calls, ["tap", "back"])

    def test_collect_visible_chats_preserves_collection_error_when_back_fails(self):
        calls = []
        contact = Contact(
            name="小赵",
            last_time="上午 10:45",
            preview="",
            bounds=(0, 500, 1256, 678),
            tap_x=628,
            tap_y=589,
            raw_texts=["小赵"],
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("wechat_collect.device.dump_layout", return_value=Path(temp_dir) / "page.json"), \
                    patch("wechat_collect.device.load_ui_tree", return_value={}), \
                    patch("wechat_collect.device.extract_contacts", return_value=[contact]), \
                    patch("wechat_collect.device.tap", side_effect=lambda *args, **kwargs: calls.append("tap")), \
                    patch("wechat_collect.device.press_back", side_effect=RuntimeError("back failed")), \
                    patch("wechat_collect.device.build_chat_payload", side_effect=ValueError("bad dump")):
                with self.assertRaisesRegex(ValueError, "bad dump") as cm:
                    collect_visible_chats(CollectOptions(dump_dir=temp_dir, wait=0))

        self.assertEqual(calls, ["tap"])
        self.assertIsInstance(cm.exception.__context__, RuntimeError)

    def test_collect_visible_chats_rejects_unbounded_contact_before_tapping(self):
        calls = []
        contact = Contact(
            name="坏数据",
            last_time="",
            preview="",
            bounds=None,
            tap_x=0,
            tap_y=0,
            raw_texts=["坏数据"],
        )

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch("wechat_collect.device.dump_layout", return_value=Path(temp_dir) / "home.json"), \
                    patch("wechat_collect.device.load_ui_tree", return_value={}), \
                    patch("wechat_collect.device.extract_contacts", return_value=[contact]), \
                    patch("wechat_collect.device.tap", side_effect=lambda *args, **kwargs: calls.append("tap")), \
                    patch("wechat_collect.device.press_back", side_effect=lambda *args, **kwargs: calls.append("back")):
                with self.assertRaises(ValueError):
                    collect_visible_chats(CollectOptions(dump_dir=temp_dir, wait=0))

        self.assertEqual(calls, [])


class WechatCollectServiceTests(unittest.TestCase):
    def test_wechat_collect_defaults_are_declared_in_single_config_module(self):
        from wechat_collect import config as collect_config
        from wechat_collect import collector as collect_compat

        expected_defaults = {
            "DEFAULT_DAYS": 7,
            "DEFAULT_MAX_CONTACTS": 10,
            "DEFAULT_SWIPE_SPEED": 2000,
            "DEFAULT_HISTORY_SWIPE_RATIO": 0.4,
            "DEFAULT_STABLE_SWIPES": 3,
            "DEFAULT_MAX_HISTORY_SWIPES": 80,
            "DEFAULT_WAIT": 1.0,
            "DEFAULT_MAX_LIST_SWIPES": 20,
            "DEFAULT_HDC_TIMEOUT": 20,
        }

        for name, expected in expected_defaults.items():
            with self.subTest(name=name):
                self.assertEqual(getattr(collect_config, name), expected)
                self.assertEqual(getattr(wechat_collect_service, name), getattr(collect_config, name))

        self.assertEqual(collect_compat.DEFAULT_SWIPE_SPEED, collect_config.DEFAULT_SWIPE_SPEED)
        self.assertEqual(collect_compat.DEFAULT_HISTORY_SWIPE_RATIO, collect_config.DEFAULT_HISTORY_SWIPE_RATIO)
        self.assertEqual(collect_compat.BOUNDARY_OVERLAP_RATIO, collect_config.BOUNDARY_OVERLAP_RATIO)
        self.assertEqual(wechat_collect_service.WECHAT_BUNDLES, collect_config.WECHAT_BUNDLES)
        self.assertEqual(wechat_collect_service.SUPPORTED_MODES, collect_config.SUPPORTED_MODES)

    def test_wechat_collect_defaults_match_runtime_swipe_parameters(self):
        request = normalize_collect_request({})

        self.assertEqual(request.swipe_speed, 2000)
        self.assertEqual(request.history_swipe_ratio, 0.4)
        self.assertEqual(DEFAULT_SWIPE_SPEED, 2000)
        self.assertEqual(DEFAULT_HISTORY_SWIPE_RATIO, 0.4)
        self.assertEqual(wechat_collect_service.DEFAULT_SWIPE_SPEED, 2000)
        self.assertEqual(wechat_collect_service.DEFAULT_HISTORY_SWIPE_RATIO, 0.4)

    def test_normalize_collect_request_clamps_supported_ranges(self):
        request = normalize_collect_request({
            "days": 120,
            "max_contacts": 80,
            "swipe_speed": 2500,
            "history_swipe_ratio": 0.65,
            "stable_swipes": 3,
            "max_history_swipes": 80,
            "wait": 1.0,
        })

        self.assertEqual(request.mode, "recent_contacts")
        self.assertEqual(request.days, 90)
        self.assertEqual(request.max_contacts, 50)
        self.assertEqual(request.swipe_speed, 2500)

    def test_normalize_collect_request_requires_target_contact_name(self):
        with self.assertRaisesRegex(ValueError, "target_contact"):
            normalize_collect_request({"mode": "target_contact", "days": 7})

    def test_normalize_collect_request_rejects_non_object_payload(self):
        for payload in [None, [], "bad"]:
            with self.subTest(payload=payload):
                with self.assertRaisesRegex(ValueError, "payload must be an object"):
                    normalize_collect_request(payload)

    def test_normalize_collect_request_rejects_non_finite_float_fields(self):
        invalid_payloads = [
            {"wait": "nan"},
            {"wait": float("nan")},
            {"history_swipe_ratio": "inf"},
            {"history_swipe_ratio": float("-inf")},
        ]

        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                with self.assertRaisesRegex(ValueError, "finite"):
                    normalize_collect_request(payload)

    def test_normalize_collect_request_rejects_non_string_text_fields(self):
        invalid_payloads = [
            {"mode": 1},
            {"mode": "target_contact", "target_contact": []},
            {"output_dir": {}},
        ]

        for payload in invalid_payloads:
            with self.subTest(payload=payload):
                with self.assertRaises(ValueError):
                    normalize_collect_request(payload)

    def test_collect_recent_contacts_uses_full_current_page_before_swiping(self):
        first_dump = load_fixture("home.json")
        swipes = []

        def dump_provider():
            return first_dump

        def swipe_next(root):
            swipes.append(root)

        contacts = collect_recent_contacts_from_dumps(
            dump_provider,
            swipe_next,
            max_contacts=2,
            stable_swipes=2,
            max_list_swipes=3,
        )

        self.assertEqual([contact.name for contact in contacts], ["小赵", "项目群"])
        self.assertEqual(swipes, [])

    def test_collect_recent_contacts_scrolls_until_unique_limit(self):
        first_dump = load_fixture("home.json")
        second_dump = json.loads(json.dumps(first_dump, ensure_ascii=False))
        second_dump["children"][0]["children"][0]["children"][0]["attributes"]["text"] = "新联系人"
        dumps = [first_dump, second_dump, second_dump, second_dump]
        swipes = []

        def dump_provider():
            return dumps[len(swipes)]

        def swipe_next(root):
            swipes.append(root)

        contacts = collect_recent_contacts_from_dumps(
            dump_provider,
            swipe_next,
            max_contacts=4,
            stable_swipes=2,
            max_list_swipes=3,
        )

        self.assertEqual([contact.name for contact in contacts], ["小赵", "项目群", "文件传输助手", "新联系人"])
        self.assertEqual(len(swipes), 1)

    def test_daily_log_entries_include_complete_message_excerpt(self):
        chat_payload = build_chat_payload(load_fixture("chat_xiao_zhao.json"))
        conversations = [{
            "contact": {"name": "小赵"},
            "title": chat_payload["title"],
            "messages": chat_payload["messages"],
            "time_range": {
                "start": "2026-06-08",
                "end": "2026-06-11",
            },
        }]

        entries = daily_log_entries_from_conversations(conversations, days=7)

        self.assertEqual(len(entries), 1)
        self.assertTrue(entries[0].startswith("## 微信联系人「小赵」最近 7 天消息采集"))
        self.assertIn("### 完整消息摘录", entries[0])
        self.assertIn("我：我想要买一个iPhone 17Pro", entries[0])
        self.assertIn("小赵：需要给妹妹买一些少儿读物", entries[0])

    def test_uidump_action_builds_hdc_commands_and_normalizes_dump_name(self):
        commands = []

        def fake_run_hdc(args):
            commands.append(args)
            if args[:4] == ["hdc", "-t", "SERIAL", "file"]:
                output_dir = Path(args[-1])
                (output_dir / "custom_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(wechat_collect_service, "load_ui_tree", return_value={"root": True}):
                result = wechat_collect_service.uidump_action({
                    "remote_path": "/data/local/tmp/custom_tree.json",
                    "output_dir": temp_dir,
                }, "hdc -t SERIAL")

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["ui_tree"], {"root": True})
            self.assertEqual(result["dump_path"], str(Path(temp_dir) / "ui_tree.json"))
            self.assertTrue((Path(temp_dir) / "ui_tree.json").exists())

        self.assertEqual(commands, [
            ["hdc", "-t", "SERIAL", "shell", "uitest", "dumpLayout", "-p", "/data/local/tmp/custom_tree.json"],
            ["hdc", "-t", "SERIAL", "file", "recv", "/data/local/tmp/custom_tree.json", temp_dir],
        ])

    def test_uidump_action_rejects_remote_path_traversal(self):
        bad_paths = [
            "/data/local/tmp/../x.json",
            "/data/local/tmp/",
            "/data/local/tmp/not_json.txt",
            "/sdcard/ui_tree.json",
        ]

        for remote_path in bad_paths:
            with self.subTest(remote_path=remote_path):
                with patch.object(wechat_collect_service, "_run_hdc") as run_hdc:
                    with self.assertRaises(ValueError):
                        wechat_collect_service.uidump_action({"remote_path": remote_path}, "hdc")
                run_hdc.assert_not_called()

    def test_uidump_action_rejects_invalid_output_dir(self):
        with self.assertRaisesRegex(ValueError, "output_dir must be a string"):
            wechat_collect_service.uidump_action({"output_dir": []}, "hdc")

        with tempfile.NamedTemporaryFile() as temp_file:
            with self.assertRaisesRegex(ValueError, "output_dir is not a directory"):
                wechat_collect_service.uidump_action({"output_dir": temp_file.name}, "hdc")

    def test_run_hdc_converts_timeout_to_runtime_error(self):
        with patch.object(
            wechat_collect_service.subprocess,
            "run",
            side_effect=subprocess.TimeoutExpired(["hdc", "list", "targets"], 20),
        ):
            with self.assertRaisesRegex(RuntimeError, "timed out after 20s"):
                wechat_collect_service._run_hdc(["hdc", "list", "targets"])

    def test_collect_action_recent_contacts_writes_artifacts_with_fake_device(self):
        dumps = [load_fixture("home.json"), load_fixture("chat_xiao_zhao.json")]
        taps = []
        backs = []

        def dump_provider(path):
            root = dumps.pop(0)
            path.write_text(json.dumps(root, ensure_ascii=False), encoding="utf-8")
            return root

        def tap_contact(contact):
            taps.append(contact.name)

        def press_back():
            backs.append("back")

        with tempfile.TemporaryDirectory() as temp_dir:
            result = wechat_collect_service.collect_action_with_device(
                {
                    "mode": "recent_contacts",
                    "days": 7,
                    "max_contacts": 1,
                    "output_dir": temp_dir,
                    "wait": 0,
                },
                dump_provider=dump_provider,
                tap_contact=tap_contact,
                press_back=press_back,
                swipe_history=lambda chat_root, request: None,
                gui_search=lambda name: None,
            )

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["contacts_collected"], 1)
            self.assertEqual(taps, ["小赵"])
            self.assertEqual(backs, ["back"])
            self.assertTrue(Path(result["artifacts"]["aggregate_json"]).exists())
            self.assertTrue(Path(result["artifacts"]["aggregate_markdown"]).exists())
            self.assertEqual(result["conversations"][0]["title"], "小赵")
            self.assertEqual(result["conversations"][0]["history_mode"], "visible_page_only")
            self.assertEqual(result["conversations"][0]["time_range"]["mode"], "visible_page_only")
            self.assertTrue(result["daily_log_entries"][0].startswith("## 微信联系人「小赵」当前可见页面消息采集"))
            self.assertIn("请求最近 7 天，未展开历史", result["daily_log_entries"][0])

            loaded = json.loads(Path(result["artifacts"]["aggregate_json"]).read_text(encoding="utf-8"))
            self.assertEqual(loaded["contacts_collected"], result["contacts_collected"])
            self.assertEqual(loaded["conversations"][0]["contact"]["bounds"], result["conversations"][0]["contact"]["bounds"])
            self.assertIsInstance(result["conversations"][0]["contact"]["bounds"], list)

    def test_collect_action_target_contact_requires_gui_search_success(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(RuntimeError, "指定联系人搜索失败"):
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    dump_provider=lambda path: load_fixture("chat_xiao_zhao.json"),
                    tap_contact=lambda contact: None,
                    press_back=lambda: None,
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: False,
                )

    def test_collect_action_target_contact_rejects_structured_search_error(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(RuntimeError, "指定联系人搜索失败"):
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    dump_provider=lambda path: load_fixture("chat_xiao_zhao.json"),
                    tap_contact=lambda contact: None,
                    press_back=lambda: None,
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: {"status": "error"},
                )

    def test_collect_action_target_contact_success_presses_back(self):
        backs = []

        def dump_provider(path):
            root = load_fixture("chat_xiao_zhao.json")
            path.write_text(json.dumps(root, ensure_ascii=False), encoding="utf-8")
            return root

        with tempfile.TemporaryDirectory() as temp_dir:
            result = wechat_collect_service.collect_action_with_device(
                {
                    "mode": "target_contact",
                    "target_contact": "小赵",
                    "output_dir": temp_dir,
                    "wait": 0,
                },
                dump_provider=dump_provider,
                tap_contact=lambda contact: None,
                press_back=lambda: backs.append("back"),
                swipe_history=lambda chat_root, request: None,
                gui_search=lambda name: {"status": "ok"},
            )

        self.assertEqual(result["contacts_collected"], 1)
        self.assertEqual(backs, ["back"])

    def test_collect_action_target_contact_failure_after_search_still_presses_back(self):
        backs = []

        def dump_provider(path):
            raise ValueError("bad target dump")

        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(ValueError, "bad target dump"):
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    dump_provider=dump_provider,
                    tap_contact=lambda contact: None,
                    press_back=lambda: backs.append("back"),
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: True,
                )

        self.assertEqual(backs, ["back"])

    def test_collect_action_target_contact_preserves_collection_error_when_back_fails(self):
        def dump_provider(path):
            raise ValueError("bad target dump")

        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(ValueError, "bad target dump") as cm:
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    dump_provider=dump_provider,
                    tap_contact=lambda contact: None,
                    press_back=lambda: (_ for _ in ()).throw(RuntimeError("back failed")),
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: True,
                )

        self.assertIsInstance(cm.exception.__context__, RuntimeError)
        self.assertEqual(str(cm.exception.__context__), "back failed")
        self.assertIsNone(cm.exception.__context__.__context__)

    def test_collect_action_recent_contact_failure_after_tap_still_presses_back(self):
        dumps = [load_fixture("home.json")]
        calls = []

        def dump_provider(path):
            if dumps:
                root = dumps.pop(0)
                path.write_text(json.dumps(root, ensure_ascii=False), encoding="utf-8")
                return root
            raise ValueError("bad chat dump")

        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(ValueError, "bad chat dump"):
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "recent_contacts",
                        "max_contacts": 1,
                        "max_history_swipes": 0,
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    dump_provider=dump_provider,
                    tap_contact=lambda contact: calls.append(f"tap:{contact.name}"),
                    press_back=lambda: calls.append("back"),
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: None,
                )

        self.assertEqual(calls, ["tap:小赵", "back"])

    def test_collect_action_recent_contacts_scrolls_home_list_with_fake_device(self):
        first_home = load_fixture("home.json")
        second_home = json.loads(json.dumps(first_home, ensure_ascii=False))
        second_home["children"][0]["children"][0]["children"][0]["attributes"]["text"] = "新联系人"
        home_dumps = [first_home, second_home]
        chat_dump = load_fixture("chat_xiao_zhao.json")
        taps = []
        swipes = []

        def dump_provider(path):
            if path.name.startswith("home"):
                root = home_dumps.pop(0)
            else:
                root = chat_dump
            path.write_text(json.dumps(root, ensure_ascii=False), encoding="utf-8")
            return root

        with tempfile.TemporaryDirectory() as temp_dir:
            result = wechat_collect_service.collect_action_with_device(
                {
                    "mode": "recent_contacts",
                    "days": 7,
                    "max_contacts": 4,
                    "stable_swipes": 2,
                    "max_list_swipes": 2,
                    "output_dir": temp_dir,
                    "wait": 0,
                },
                dump_provider=dump_provider,
                tap_contact=lambda contact: taps.append(contact.name),
                press_back=lambda: None,
                swipe_history=lambda chat_root, request: None,
                swipe_contacts=lambda home_root, request: swipes.append("swipe"),
                gui_search=lambda name: None,
            )

        self.assertEqual(swipes, ["swipe"])
        self.assertIn("新联系人", taps)
        self.assertEqual(result["contacts_collected"], 4)

    def test_collect_action_adapter_preserves_full_hdc_prefix(self):
        commands = []

        def fake_run_hdc(args):
            commands.append(args)
            if args[:7] == ["hdc", "-t", "SERIAL", "shell", "bm", "dump", "-n"]:
                return subprocess.CompletedProcess(args, 0, "mainAbility: EntryAbility\n", "")
            if args[:5] == ["hdc", "-t", "SERIAL", "file", "recv"]:
                output_dir = Path(args[-1])
                (output_dir / "ui_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(
                        wechat_collect_service,
                        "load_ui_tree",
                        side_effect=[
                            load_fixture("home.json"),
                            load_fixture("chat_xiao_zhao.json"),
                            load_fixture("history_009.json"),
                        ],
                    ):
                result = wechat_collect_service.collect_action(
                    {
                        "mode": "recent_contacts",
                        "days": 7,
                        "max_contacts": 1,
                        "max_history_swipes": 0,
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    "hdc -t SERIAL",
                    gui_search=lambda name: None,
                )

        self.assertEqual(result["status"], "ok")
        start_command = [
            "hdc", "-t", "SERIAL", "shell", "aa", "start", "-a", "EntryAbility", "-b", "com.tencent.wechat"
        ]
        dump_command = ["hdc", "-t", "SERIAL", "shell", "uitest", "dumpLayout", "-p", "/data/local/tmp/ui_tree.json"]
        self.assertIn(start_command, commands)
        self.assertIn(
            dump_command,
            commands,
        )
        self.assertLess(commands.index(start_command), commands.index(dump_command))
        self.assertIn(["hdc", "-t", "SERIAL", "shell", "uitest", "uiInput", "click", "628", "589"], commands)
        self.assertIn(["hdc", "-t", "SERIAL", "shell", "uitest", "uiInput", "keyEvent", "Back"], commands)

    def test_collect_action_prefers_hmdriver2_for_ui_operations(self):
        commands = []
        driver_calls = []

        class FakeDriver:
            def force_start_app(self, bundle):
                driver_calls.append(("force_start_app", bundle))

            def shell(self, command):
                driver_calls.append(("shell", command))

            def click(self, x, y):
                driver_calls.append(("click", x, y))

            def swipe(self, x1, y1, x2, y2, speed=1000):
                driver_calls.append(("swipe", x1, y1, x2, y2, speed))

            def press_key(self, key):
                driver_calls.append(("press_key", key))

        fake_driver = FakeDriver()

        def fake_driver_call(label, operation):
            driver_calls.append(("driver_call", label))
            return operation(fake_driver)

        def fake_run_hdc(args):
            commands.append(args)
            if args[:5] == ["hdc", "-t", "SERIAL", "file", "recv"]:
                output_dir = Path(args[-1])
                (output_dir / "ui_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(
                        wechat_collect_service,
                        "load_ui_tree",
                        side_effect=[
                            load_fixture("home.json"),
                            load_fixture("chat_xiao_zhao.json"),
                            load_fixture("history_009.json"),
                        ],
                    ):
                result = wechat_collect_service.collect_action(
                    {
                        "mode": "recent_contacts",
                        "days": 7,
                        "max_contacts": 1,
                        "max_history_swipes": 1,
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    "hdc -t SERIAL",
                    gui_search=lambda name: None,
                    driver_call=fake_driver_call,
                )

        self.assertEqual(result["status"], "ok")
        self.assertIn(("force_start_app", "com.tencent.wechat"), driver_calls)
        self.assertIn(("shell", "uitest dumpLayout -p /data/local/tmp/ui_tree.json"), driver_calls)
        self.assertIn(("click", 628, 589), driver_calls)
        self.assertIn(("press_key", 2), driver_calls)
        self.assertEqual(
            [command for command in commands if command[:4] == ["hdc", "-t", "SERIAL", "shell"]],
            [],
        )

    def test_collect_action_scrolls_chat_history_for_requested_days(self):
        commands = []
        driver_calls = []

        class FakeDriver:
            def force_start_app(self, bundle):
                driver_calls.append(("force_start_app", bundle))

            def shell(self, command):
                driver_calls.append(("shell", command))

            def click(self, x, y):
                driver_calls.append(("click", x, y))

            def swipe(self, x1, y1, x2, y2, speed=1000):
                driver_calls.append(("swipe", x1, y1, x2, y2, speed))

            def press_key(self, key):
                driver_calls.append(("press_key", key))

        fake_driver = FakeDriver()

        def fake_driver_call(label, operation):
            driver_calls.append(("driver_call", label))
            return operation(fake_driver)

        def fake_run_hdc(args):
            commands.append(args)
            if args[:5] == ["hdc", "-t", "SERIAL", "file", "recv"]:
                output_dir = Path(args[-1])
                (output_dir / "ui_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(
                        wechat_collect_service,
                        "load_ui_tree",
                        side_effect=[
                            load_fixture("home.json"),
                            load_fixture("chat_xiao_zhao.json"),
                            load_fixture("history_009.json"),
                        ],
                    ):
                result = wechat_collect_service.collect_action(
                    {
                        "mode": "recent_contacts",
                        "days": 7,
                        "max_contacts": 1,
                        "max_history_swipes": 1,
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    "hdc -t SERIAL",
                    gui_search=lambda name: None,
                    driver_call=fake_driver_call,
                )

        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["conversations"][0]["snapshots"]), 2)
        self.assertEqual(result["conversations"][0]["history_mode"], "history_scrolled")
        self.assertIn(("driver_call", "Driver.swipe(chat_history)"), driver_calls)
        self.assertTrue(any(call[0] == "swipe" for call in driver_calls))
        self.assertNotIn("当前可见页面消息采集", result["daily_log_entries"][0])

    def test_collect_action_target_contact_uses_hmdriver_search_without_gui_agent(self):
        commands = []
        driver_calls = []

        class FakeDriver:
            def force_start_app(self, bundle):
                driver_calls.append(("force_start_app", bundle))

            def shell(self, command):
                driver_calls.append(("shell", command))

            def click(self, x, y):
                driver_calls.append(("click", x, y))

            def input_text(self, text):
                driver_calls.append(("input_text", text))

            def swipe(self, x1, y1, x2, y2, speed=1000):
                driver_calls.append(("swipe", x1, y1, x2, y2, speed))

            def press_key(self, key):
                driver_calls.append(("press_key", key))

        fake_driver = FakeDriver()

        def fake_driver_call(label, operation):
            driver_calls.append(("driver_call", label))
            return operation(fake_driver)

        def fake_run_hdc(args):
            commands.append(args)
            if args[:5] == ["hdc", "-t", "SERIAL", "file", "recv"]:
                output_dir = Path(args[-1])
                (output_dir / "ui_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        def forbidden_gui_search(name):
            raise AssertionError("GUI agent search should not be required")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(
                        wechat_collect_service,
                        "load_ui_tree",
                        side_effect=[
                            search_home_root(),
                            search_results_root(),
                            load_fixture("chat_xiao_zhao.json"),
                            load_fixture("history_009.json"),
                        ],
                    ):
                result = wechat_collect_service.collect_action(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "days": 7,
                        "max_history_swipes": 0,
                        "output_dir": temp_dir,
                        "wait": 0,
                    },
                    "hdc -t SERIAL",
                    gui_search=forbidden_gui_search,
                    driver_call=fake_driver_call,
                )

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["target_contact"], "小赵")
        self.assertEqual(result["contacts_collected"], 1)
        self.assertEqual(result["conversations"][0]["contact"]["name"], "小赵")
        self.assertTrue(result["daily_log_entries"][0].startswith("## 微信联系人「小赵」"))
        self.assertIn(("input_text", "小赵"), driver_calls)
        self.assertIn(("click", 620, 175), driver_calls)
        self.assertIn(("click", 628, 410), driver_calls)
        self.assertEqual(
            [command for command in commands if command[:4] == ["hdc", "-t", "SERIAL", "shell"]],
            [],
        )

    def test_collect_action_target_contact_uses_single_requested_contact(self):
        commands = []

        def fake_run_hdc(args):
            commands.append(args)
            if args[:3] == ["hdc", "file", "recv"]:
                output_dir = Path(args[-1])
                (output_dir / "ui_tree.json").write_text("{}", encoding="utf-8")
            return subprocess.CompletedProcess(args, 0, "", "")

        with tempfile.TemporaryDirectory() as temp_dir:
            with patch.object(wechat_collect_service, "_run_hdc", side_effect=fake_run_hdc), \
                    patch.object(wechat_collect_service, "load_ui_tree", return_value=load_fixture("chat_xiao_zhao.json")):
                result = wechat_collect_service.collect_action({
                    "mode": "target_contact",
                    "target_contact": "小赵",
                    "max_contacts": 10,
                    "output_dir": temp_dir,
                    "wait": 0,
                }, "hdc", gui_search=lambda name: True)

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["contacts_requested"], 1)
        self.assertEqual(result["contacts_collected"], 1)
        self.assertEqual(result["target_contact"], "小赵")

    def test_recent_contacts_fails_when_no_contacts_are_detected(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            with self.assertRaisesRegex(RuntimeError, "未识别到微信最近联系人"):
                wechat_collect_service.collect_action_with_device(
                    {
                        "mode": "recent_contacts",
                        "max_contacts": 2,
                        "stable_swipes": 1,
                        "max_list_swipes": 0,
                        "output_dir": temp_dir,
                    },
                    dump_provider=lambda path: {},
                    tap_contact=lambda contact: None,
                    press_back=lambda: None,
                    swipe_history=lambda chat_root, request: None,
                    gui_search=lambda name: None,
                    swipe_contacts=lambda home_root, request: None,
                )

    def test_collect_action_default_run_id_uses_execution_time(self):
        dumps = [load_fixture("home.json"), load_fixture("chat_xiao_zhao.json")]

        def dump_provider(path):
            root = dumps.pop(0)
            path.write_text(json.dumps(root, ensure_ascii=False), encoding="utf-8")
            return root

        result = wechat_collect_service.collect_action_with_device(
            {
                "mode": "recent_contacts",
                "max_contacts": 1,
                "max_history_swipes": 0,
                "output_dir": "",
            },
            dump_provider=dump_provider,
            tap_contact=lambda contact: None,
            press_back=lambda: None,
            swipe_history=lambda chat_root, request: None,
            gui_search=lambda name: None,
        )

        self.assertRegex(result["run_id"], r"^wechat-\d{8}T\d{6}$")


if __name__ == "__main__":
    unittest.main()
