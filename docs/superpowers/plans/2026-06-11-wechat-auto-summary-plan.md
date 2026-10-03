# WeChat Auto Summary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a switchable WeChat auto-summary collection source that uses PC-side UI dump collection, stores raw artifacts, writes contact-level daily-log entries, and keeps existing DataManager/Workflow paths isolated.

**Architecture:** Move the reusable AUTOwechat UI dump parser and collection logic into an independent Python package under `entry/src/main/python/wechat_collect`. Extend `hdc_server.py` with small `uidump` and `wechat_collect` workflow actions that delegate to that package. Add ArkTS settings, summary-page controls, an HDC client, and a storage helper that writes raw artifacts plus DataManager-compatible daily-log files.

**Tech Stack:** Python 3 standard library, HarmonyOS HDC `uitest dumpLayout`, ArkTS/ArkUI, `@StorageLink`/`PersistentStorage`, existing `DataManagerStorage`, Hypium unit tests, Python `unittest`.

---

## Scope Check

This is one feature even though it touches PC Python and App ArkTS, because both sides are joined by one explicit `wechat_collect` interface and produce one existing DataManager input: daily-log. Do not refactor unrelated Workflow, AgentRouter, Gallery, or Chat code.

## File Structure

- Create `entry/src/main/python/wechat_collect/__init__.py`
  Exports the public collection request/result APIs for `hdc_server.py` and tests.
- Create `entry/src/main/python/wechat_collect/collector.py`
  Starts as a direct migration of `AUTOwechat/wechat_ui_dump.py`; owns UI tree parsing, chat message extraction, history swipes, Markdown rendering, and existing single-page collection behavior.
- Create `entry/src/main/python/wechat_collect/service.py`
  Owns request validation, recent-contact scrolling orchestration, target-contact orchestration, run metadata, and artifact path conventions.
- Create `entry/src/main/python/wechat_collect/fixtures/`
  Contains minimal copied UI dump fixtures used by tests: `home.json`, `chat_xiao_zhao.json`, `history_009.json`, `history_010.json`.
- Create `entry/src/main/python/test_wechat_collect.py`
  Tests migrated parser behavior, request validation, recent-contact list scrolling logic, and daily output shape without a device.
- Modify `entry/src/main/python/hdc_server.py`
  Adds optional import for `wechat_collect.service`, a `uidump` workflow action, and a `wechat_collect` workflow action.
- Modify `entry/src/main/python/test_hdc_server_workflow.py`
  Adds bridge tests that monkeypatch the service module and avoid HDC/device access.
- Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryTypes.ets`
  Defines settings keys, defaults, validation helpers, request/response interfaces, and small view-model helpers.
- Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryClient.ets`
  Posts typed `wechat_collect` requests to existing `/api/workflow`.
- Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryStorage.ets`
  Saves raw artifacts and writes `workflows/daily-log/YYYY-MM-DD/com.tencent.mm__wechat_auto_summary__<run_id>.md`.
- Create `entry/src/test/WechatAutoSummaryUnit.test.ets`
  Tests ArkTS validation, daily-log rendering, and view-state helpers.
- Modify `entry/src/test/List.test.ets`
  Registers the new Hypium test.
- Modify `entry/src/main/ets/pages/settings/SettingsCenterPage.ets`
  Adds WeChat settings controls to the Data Collection section.
- Modify `entry/src/main/ets/pages/collection/CollectionPage.ets`
  Adds the gated WeChat collection card and turns “新增采集源” into a settings-navigation action.
- Modify `entry/src/main/ets/pages/Index.ets`
  Registers settings defaults, lifts the selected Settings section state, wires CollectionPage callbacks, runs collection, saves artifacts, and optionally triggers existing DataManager sync.

## Task 1: Migrate AUTOwechat Parser Into a Local Package

**Files:**
- Create: `entry/src/main/python/wechat_collect/__init__.py`
- Create: `entry/src/main/python/wechat_collect/collector.py`
- Create: `entry/src/main/python/wechat_collect/fixtures/home.json`
- Create: `entry/src/main/python/wechat_collect/fixtures/chat_xiao_zhao.json`
- Create: `entry/src/main/python/wechat_collect/fixtures/history_009.json`
- Create: `entry/src/main/python/wechat_collect/fixtures/history_010.json`
- Create: `entry/src/main/python/test_wechat_collect.py`

- [ ] **Step 1: Write the failing parser migration tests**

Create `entry/src/main/python/test_wechat_collect.py` with:

```python
import json
import unittest
from datetime import datetime
from pathlib import Path

from wechat_collect.collector import (
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

        self.assertGreaterEqual(len(contacts), 3)
        self.assertEqual(contacts[0].name, "小赵")
        self.assertEqual(contacts[0].last_time, "上午 10:45")
        self.assertEqual(contacts[0].tap_x, 628)
        self.assertEqual(contacts[0].tap_y, 589)

    def test_extracts_chat_title_and_messages(self):
        root = load_fixture("chat_xiao_zhao.json")

        self.assertEqual(extract_chat_title(root), "小赵")
        messages = extract_chat_messages(root)
        self.assertEqual(messages[0].kind, "time")
        self.assertEqual(messages[0].text, "星期一 下午 03:47")
        self.assertIn(("message", "self", "我想要买一个iPhone 17Pro"),
                      [(m.kind, m.sender, m.text) for m in messages])

    def test_payload_uses_title_as_other_sender(self):
        payload = build_chat_payload(load_fixture("chat_xiao_zhao.json"))

        senders = [m["sender"] for m in payload["messages"] if m["kind"] == "message"]
        self.assertIn("小赵", senders)
        self.assertNotIn("other", senders)

    def test_parses_wechat_time_labels(self):
        reference = datetime(2026, 6, 11, 12, 0)

        self.assertEqual(parse_chat_time("上午 10:45", reference), datetime(2026, 6, 11, 10, 45))
        self.assertEqual(parse_chat_time("昨天下午 07:39", reference), datetime(2026, 6, 10, 19, 39))
        self.assertEqual(parse_chat_time("星期一 下午 03:47", reference), datetime(2026, 6, 8, 15, 47))
        self.assertIsNone(parse_chat_time("以上是打招呼的内容", reference))

    def test_snapshot_merge_deduplicates_boundary_overlap(self):
        payload = build_chat_payload_from_snapshots(
            [load_fixture("history_009.json"), load_fixture("history_010.json")],
            fallback_title="小赵",
            reference_now=datetime(2026, 6, 11, 12, 0),
        )
        texts = [message["text"] for message in payload["messages"]]

        self.assertEqual(texts.count("planner优先使用 123.60.91.241:9003"), 1)

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


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the parser tests to verify they fail**

Run:

```bash
python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: FAIL with `ModuleNotFoundError: No module named 'wechat_collect'`.

- [ ] **Step 3: Copy the parser and fixtures**

Run:

```bash
mkdir -p entry/src/main/python/wechat_collect/fixtures
cp /Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat/wechat_ui_dump.py entry/src/main/python/wechat_collect/collector.py
cp /Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat/examples/首页.json entry/src/main/python/wechat_collect/fixtures/home.json
cp /Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat/examples/聊天页面-小赵.json entry/src/main/python/wechat_collect/fixtures/chat_xiao_zhao.json
cp /Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat/dumps/chat_01_小赵_history_009.json entry/src/main/python/wechat_collect/fixtures/history_009.json
cp /Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat/dumps/chat_01_小赵_history_010.json entry/src/main/python/wechat_collect/fixtures/history_010.json
```

Create `entry/src/main/python/wechat_collect/__init__.py`:

```python
"""微信 UI dump 采集模块。"""

from .collector import (
    Contact,
    build_chat_payload,
    build_chat_payload_from_snapshots,
    compute_history_swipe,
    extract_chat_messages,
    extract_chat_title,
    extract_contacts,
    parse_chat_time,
    render_markdown,
)

__all__ = [
    "Contact",
    "build_chat_payload",
    "build_chat_payload_from_snapshots",
    "compute_history_swipe",
    "extract_chat_messages",
    "extract_chat_title",
    "extract_contacts",
    "parse_chat_time",
    "render_markdown",
]
```

- [ ] **Step 4: Run parser tests to verify they pass**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: PASS.

- [ ] **Step 5: Commit parser migration**

Run:

```bash
git add -f entry/src/main/python/wechat_collect entry/src/main/python/test_wechat_collect.py
git commit -m "迁移微信UIDump解析模块"
```

## Task 2: Add WeChat Collection Service Validation and Recent Contact Scrolling

**Files:**
- Create: `entry/src/main/python/wechat_collect/service.py`
- Modify: `entry/src/main/python/wechat_collect/__init__.py`
- Modify: `entry/src/main/python/test_wechat_collect.py`

- [ ] **Step 1: Add failing service tests**

Append to `entry/src/main/python/test_wechat_collect.py`:

```python
import tempfile
from types import SimpleNamespace
from unittest.mock import Mock

from wechat_collect.service import (
    WechatCollectRequest,
    collect_recent_contacts_from_dumps,
    daily_log_entries_from_conversations,
    normalize_collect_request,
)


class WechatCollectServiceTests(unittest.TestCase):
    def test_normalize_collect_request_clamps_supported_ranges(self):
        request = normalize_collect_request({
            "mode": "recent_contacts",
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

    def test_collect_recent_contacts_scrolls_until_unique_limit(self):
        home = load_fixture("home.json")
        second_home = load_fixture("home.json")
        first = extract_contacts(home)[0]
        second_home["children"][0]["children"][0]["children"][0]["attributes"]["text"] = "新联系人"
        dumps = [home, second_home]
        swipes = []

        contacts = collect_recent_contacts_from_dumps(
            dump_provider=lambda: dumps.pop(0),
            swipe_next=lambda root: swipes.append(root),
            max_contacts=2,
            stable_swipes=2,
            max_list_swipes=3,
        )

        self.assertEqual([contact.name for contact in contacts[:2]], [first.name, "新联系人"])
        self.assertEqual(len(swipes), 1)

    def test_daily_log_entries_include_complete_message_excerpt(self):
        chat_payload = build_chat_payload(load_fixture("chat_xiao_zhao.json"))
        conversations = [{
            "title": "小赵",
            "contact": {"name": "小赵"},
            "messages": chat_payload["messages"],
            "time_range": {"start": "2026-06-08", "end": "2026-06-11"},
        }]

        entries = daily_log_entries_from_conversations(conversations, days=7)

        self.assertEqual(len(entries), 1)
        self.assertIn("微信联系人「小赵」最近 7 天消息采集", entries[0])
        self.assertIn("完整消息摘录", entries[0])
        self.assertIn("我：我想要买一个iPhone 17Pro", entries[0])
        self.assertIn("小赵：需要给妹妹买一些少儿读物", entries[0])
```

- [ ] **Step 2: Run service tests to verify they fail**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: FAIL with `ModuleNotFoundError: No module named 'wechat_collect.service'`.

- [ ] **Step 3: Implement service validation and pure helpers**

Create `entry/src/main/python/wechat_collect/service.py`:

```python
"""微信采集服务层：参数校验、联系人滚动、daily-log 文本生成。"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from .collector import (
    Contact,
    build_chat_payload,
    dump_layout,
    extract_contacts,
    load_ui_tree,
    markdown_path_for_json,
    press_back,
    print_json_and_markdown,
    safe_filename,
    tap,
)

DEFAULT_DAYS = 7
DEFAULT_MAX_CONTACTS = 10
DEFAULT_SWIPE_SPEED = 2500
DEFAULT_HISTORY_SWIPE_RATIO = 0.65
DEFAULT_STABLE_SWIPES = 3
DEFAULT_MAX_HISTORY_SWIPES = 80
DEFAULT_WAIT = 1.0
DEFAULT_MAX_LIST_SWIPES = 20


@dataclass(frozen=True)
class WechatCollectRequest:
    mode: str
    days: int
    max_contacts: int
    target_contact: str
    swipe_speed: int
    history_swipe_ratio: float
    stable_swipes: int
    max_history_swipes: int
    wait: float
    max_list_swipes: int
    output_dir: str


def _int_range(payload: dict[str, Any], key: str, default: int, minimum: int, maximum: int) -> int:
    value = int(payload.get(key, default))
    return max(minimum, min(maximum, value))


def _float_range(payload: dict[str, Any], key: str, default: float, minimum: float, maximum: float) -> float:
    value = float(payload.get(key, default))
    return max(minimum, min(maximum, value))


def normalize_collect_request(payload: dict[str, Any]) -> WechatCollectRequest:
    mode = str(payload.get("mode", "recent_contacts")).strip() or "recent_contacts"
    if mode not in ("recent_contacts", "target_contact"):
        raise ValueError("mode must be recent_contacts or target_contact")
    target_contact = str(payload.get("target_contact", "")).strip()
    if mode == "target_contact" and not target_contact:
        raise ValueError("target_contact is required for target_contact mode")
    return WechatCollectRequest(
        mode=mode,
        days=_int_range(payload, "days", DEFAULT_DAYS, 1, 90),
        max_contacts=_int_range(payload, "max_contacts", DEFAULT_MAX_CONTACTS, 1, 50),
        target_contact=target_contact,
        swipe_speed=_int_range(payload, "swipe_speed", DEFAULT_SWIPE_SPEED, 0, 20000),
        history_swipe_ratio=_float_range(payload, "history_swipe_ratio", DEFAULT_HISTORY_SWIPE_RATIO, 0.1, 0.95),
        stable_swipes=_int_range(payload, "stable_swipes", DEFAULT_STABLE_SWIPES, 1, 10),
        max_history_swipes=_int_range(payload, "max_history_swipes", DEFAULT_MAX_HISTORY_SWIPES, 1, 300),
        wait=_float_range(payload, "wait", DEFAULT_WAIT, 0.0, 10.0),
        max_list_swipes=_int_range(payload, "max_list_swipes", DEFAULT_MAX_LIST_SWIPES, 0, 100),
        output_dir=str(payload.get("output_dir", "")).strip(),
    )


def _contact_key(contact: Contact) -> str:
    return contact.name.strip()


def collect_recent_contacts_from_dumps(
    dump_provider: Callable[[], dict[str, Any]],
    swipe_next: Callable[[dict[str, Any]], None],
    max_contacts: int,
    stable_swipes: int,
    max_list_swipes: int,
) -> list[Contact]:
    contacts: list[Contact] = []
    seen: set[str] = set()
    stable_count = 0
    previous_names: tuple[str, ...] = ()
    for index in range(max_list_swipes + 1):
        root = dump_provider()
        page_contacts = extract_contacts(root)
        page_names = tuple(contact.name for contact in page_contacts)
        if page_names == previous_names:
            stable_count += 1
        else:
            stable_count = 0
        previous_names = page_names
        for contact in page_contacts:
            key = _contact_key(contact)
            if key and key not in seen:
                seen.add(key)
                contacts.append(contact)
                if len(contacts) >= max_contacts:
                    return contacts
        if stable_count >= stable_swipes or index >= max_list_swipes:
            break
        swipe_next(root)
    return contacts


def _message_line(message: dict[str, Any]) -> str:
    text = str(message.get("text") or "").strip()
    if not text:
        return ""
    if message.get("kind") == "time":
        return f"- {text}"
    sender = str(message.get("sender") or "未知发送人").strip()
    return f"- {sender}：{text}"


def daily_log_entries_from_conversations(conversations: list[dict[str, Any]], days: int) -> list[str]:
    entries: list[str] = []
    for conversation in conversations:
        title = str(conversation.get("title") or conversation.get("contact", {}).get("name") or "未命名会话")
        messages = conversation.get("messages") if isinstance(conversation.get("messages"), list) else []
        time_range = conversation.get("time_range") if isinstance(conversation.get("time_range"), dict) else {}
        start = str(time_range.get("start") or "")
        end = str(time_range.get("end") or "")
        range_text = f"{start} 至 {end}" if start or end else "未识别到明确范围"
        lines = [
            f"微信联系人「{title}」最近 {days} 天消息采集。采集时间范围：{range_text}；消息数：{len(messages)}。完整消息摘录："
        ]
        for message in messages:
            line = _message_line(message)
            if line:
                lines.append(line)
        entries.append("\n".join(lines))
    return entries
```

Update `entry/src/main/python/wechat_collect/__init__.py`:

```python
from .service import (
    WechatCollectRequest,
    collect_recent_contacts_from_dumps,
    daily_log_entries_from_conversations,
    normalize_collect_request,
)
```

- [ ] **Step 4: Run service tests to verify they pass**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: PASS.

- [ ] **Step 5: Commit service helpers**

Run:

```bash
git add -f entry/src/main/python/wechat_collect/service.py entry/src/main/python/wechat_collect/__init__.py entry/src/main/python/test_wechat_collect.py
git commit -m "新增微信采集服务校验"
```

## Task 3: Add hdc_server Workflow Actions

**Files:**
- Modify: `entry/src/main/python/hdc_server.py`
- Modify: `entry/src/main/python/test_hdc_server_workflow.py`

- [ ] **Step 1: Add failing hdc_server tests**

Append to `entry/src/main/python/test_hdc_server_workflow.py`:

```python
class FakeWechatCollectService:
    def __init__(self):
        self.dump_payload = None
        self.collect_payload = None

    def uidump_action(self, payload, hdc_prefix):
        self.dump_payload = dict(payload)
        return {
            "status": "ok",
            "message": "uidump ok",
            "dump_path": "/tmp/ui_tree.json",
            "ui_tree": {"attributes": {"type": "root"}},
        }

    def collect_action(self, payload, hdc_prefix, gui_search):
        self.collect_payload = dict(payload)
        return {
            "status": "ok",
            "message": "collected 1 conversations",
            "run_id": "run-1",
            "mode": payload.get("mode"),
            "days": payload.get("days"),
            "contacts_requested": payload.get("max_contacts"),
            "contacts_collected": 1,
            "conversations": [],
            "artifacts": {},
        }


class WechatWorkflowBridgeTest(unittest.TestCase):
    def test_uidump_delegates_to_wechat_service(self):
        original_service = getattr(hdc_server, "wechat_collect_service", None)
        original_is_connected = hdc_server.is_hdc_connected
        fake_service = FakeWechatCollectService()
        try:
            hdc_server.wechat_collect_service = fake_service
            hdc_server.is_hdc_connected = lambda force=False: True

            result = hdc_server.handle_workflow_action("uidump", {"remote_path": "/data/local/tmp/ui_tree.json"})

            self.assertEqual(result["status"], "ok")
            self.assertEqual(fake_service.dump_payload["remote_path"], "/data/local/tmp/ui_tree.json")
        finally:
            hdc_server.wechat_collect_service = original_service
            hdc_server.is_hdc_connected = original_is_connected

    def test_wechat_collect_delegates_to_wechat_service(self):
        original_service = getattr(hdc_server, "wechat_collect_service", None)
        original_is_connected = hdc_server.is_hdc_connected
        fake_service = FakeWechatCollectService()
        try:
            hdc_server.wechat_collect_service = fake_service
            hdc_server.is_hdc_connected = lambda force=False: True

            result = hdc_server.handle_workflow_action("wechat_collect", {
                "mode": "recent_contacts",
                "days": 7,
                "max_contacts": 10,
            })

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["run_id"], "run-1")
            self.assertEqual(fake_service.collect_payload["max_contacts"], 10)
        finally:
            hdc_server.wechat_collect_service = original_service
            hdc_server.is_hdc_connected = original_is_connected
```

- [ ] **Step 2: Run bridge tests to verify they fail**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_hdc_server_workflow.py
```

Expected: FAIL with `Unsupported workflow action: uidump`.

- [ ] **Step 3: Add hdc_server service import and actions**

Near the top of `entry/src/main/python/hdc_server.py`, after the `harmony_agent` import block, add:

```python
try:
    from wechat_collect import service as wechat_collect_service
except Exception as ex:
    wechat_collect_service = None
    print(f">> [警告] 无法导入微信 UI dump 采集模块: {ex}")
```

Add helpers near `ensure_workflow_agent_ready()`:

```python
def ensure_wechat_collect_ready():
    ensure_workflow_agent_ready()
    if wechat_collect_service is None:
        raise RuntimeError("wechat_collect module is unavailable")


def workflow_uidump_action(payload):
    ensure_wechat_collect_ready()
    return wechat_collect_service.uidump_action(payload or {}, hdc_prefix())


def workflow_wechat_collect_action(payload):
    ensure_wechat_collect_ready()
    return wechat_collect_service.collect_action(
        payload or {},
        hdc_prefix(),
        gui_search=lambda contact_name: harmony_agent.run_gui_task(f"搜索{contact_name}，进入聊天界面"),
    )
```

Extend `handle_workflow_action` before the final unsupported-action error:

```python
    if action == 'uidump':
        return workflow_uidump_action(payload)

    if action == 'wechat_collect':
        return workflow_wechat_collect_action(payload)
```

- [ ] **Step 4: Add service action functions**

Append to `entry/src/main/python/wechat_collect/service.py`:

```python
import json
import subprocess
import tempfile


def _split_hdc_prefix(hdc_prefix: str) -> list[str]:
    return [part for part in hdc_prefix.split(" ") if part]


def uidump_action(payload: dict[str, Any], hdc_prefix: str) -> dict[str, Any]:
    remote_path = str(payload.get("remote_path", "/data/local/tmp/ui_tree.json")).strip()
    if not remote_path.startswith("/data/local/tmp/"):
        raise ValueError("remote_path must be under /data/local/tmp")
    output_dir = Path(str(payload.get("output_dir", tempfile.mkdtemp(prefix="wechat-uidump-"))))
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / "ui_tree.json"
    prefix = _split_hdc_prefix(hdc_prefix)
    subprocess.run(prefix + ["shell", "uitest", "dumpLayout", "-p", remote_path], check=True)
    subprocess.run(prefix + ["file", "recv", remote_path, str(output_dir)], check=True)
    received = output_dir / Path(remote_path).name
    if received != output_path and received.exists():
        received.replace(output_path)
    return {
        "status": "ok",
        "message": "uidump ok",
        "dump_path": str(output_path),
        "ui_tree": load_ui_tree(output_path),
    }


def collect_action(payload: dict[str, Any], hdc_prefix: str, gui_search: Callable[[str], Any]) -> dict[str, Any]:
    request = normalize_collect_request(payload)
    output_dir = Path(request.output_dir or tempfile.mkdtemp(prefix="wechat-collect-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    return {
        "status": "ok",
        "message": "wechat_collect service skeleton ready",
        "run_id": datetime.now().strftime("%Y%m%d-%H%M%S-wechat"),
        "started_at": datetime.now().isoformat(timespec="seconds"),
        "finished_at": datetime.now().isoformat(timespec="seconds"),
        "mode": request.mode,
        "days": request.days,
        "contacts_requested": request.max_contacts,
        "contacts_collected": 0,
        "conversations": [],
        "artifacts": {"output_dir": str(output_dir)},
    }
```

This step intentionally returns a valid empty collection result. Later tasks replace the skeleton with full device collection while keeping the bridge contract stable.

- [ ] **Step 5: Run bridge tests to verify they pass**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_hdc_server_workflow.py
```

Expected: PASS.

- [ ] **Step 6: Commit bridge actions**

Run:

```bash
git add -f entry/src/main/python/hdc_server.py entry/src/main/python/wechat_collect/service.py entry/src/main/python/test_hdc_server_workflow.py
git commit -m "接入微信采集HDC桥接"
```

## Task 4: Complete Device Collection Orchestration

**Files:**
- Modify: `entry/src/main/python/wechat_collect/service.py`
- Modify: `entry/src/main/python/test_wechat_collect.py`

- [ ] **Step 1: Add failing orchestration tests**

Append to `WechatCollectServiceTests` in `entry/src/main/python/test_wechat_collect.py`:

```python
    def test_collect_action_recent_contacts_writes_artifacts_with_fake_device(self):
        with tempfile.TemporaryDirectory() as tmp:
            output_dir = Path(tmp)
            home = load_fixture("home.json")
            chat = load_fixture("chat_xiao_zhao.json")
            dumps = [home, chat]
            taps = []
            backs = []

            result = collect_action_with_device(
                {
                    "mode": "recent_contacts",
                    "days": 7,
                    "max_contacts": 1,
                    "output_dir": str(output_dir),
                    "wait": 0,
                },
                dump_provider=lambda path: dumps.pop(0),
                tap_contact=lambda contact: taps.append(contact.name),
                press_back=lambda: backs.append("back"),
                swipe_history=lambda root, request: None,
                gui_search=lambda contact_name: None,
            )

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["contacts_collected"], 1)
            self.assertEqual(taps, ["小赵"])
            self.assertEqual(backs, ["back"])
            self.assertTrue(Path(result["artifacts"]["aggregate_json"]).exists())
            self.assertTrue(Path(result["artifacts"]["aggregate_markdown"]).exists())
            self.assertEqual(result["conversations"][0]["title"], "小赵")
            self.assertTrue(result["daily_log_entries"][0].startswith("微信联系人「小赵」最近 7 天消息采集"))

    def test_collect_action_target_contact_requires_gui_search_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(RuntimeError, "指定联系人搜索失败"):
                collect_action_with_device(
                    {
                        "mode": "target_contact",
                        "target_contact": "小赵",
                        "days": 7,
                        "output_dir": tmp,
                    },
                    dump_provider=lambda path: load_fixture("chat_xiao_zhao.json"),
                    tap_contact=lambda contact: None,
                    press_back=lambda: None,
                    swipe_history=lambda root, request: None,
                    gui_search=lambda contact_name: False,
                )
```

Also add this import:

```python
from wechat_collect.service import collect_action_with_device
```

- [ ] **Step 2: Run orchestration tests to verify they fail**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: FAIL with `ImportError: cannot import name 'collect_action_with_device'`.

- [ ] **Step 3: Implement fake-device orchestration hook**

Append to `entry/src/main/python/wechat_collect/service.py`:

```python
def _write_payloads(output_dir: Path, payload: dict[str, Any]) -> dict[str, str]:
    aggregate_json = output_dir / "wechat_messages.json"
    print_json_and_markdown(payload, aggregate_json)
    return {
        "aggregate_json": str(aggregate_json),
        "aggregate_markdown": str(markdown_path_for_json(aggregate_json)),
        "output_dir": str(output_dir),
    }


def _conversation_from_chat_root(contact: Contact, root: dict[str, Any], dump_path: str) -> dict[str, Any]:
    chat_payload = build_chat_payload(root, fallback_title=contact.name)
    return {
        "contact": asdict(contact),
        "title": chat_payload["title"],
        "dump": dump_path,
        "snapshots": [dump_path],
        "messages": chat_payload["messages"],
        "time_range": {},
    }


def collect_action_with_device(
    payload: dict[str, Any],
    dump_provider: Callable[[Path], dict[str, Any]],
    tap_contact: Callable[[Contact], None],
    press_back: Callable[[], None],
    swipe_history: Callable[[dict[str, Any], WechatCollectRequest], None],
    gui_search: Callable[[str], Any],
) -> dict[str, Any]:
    request = normalize_collect_request(payload)
    started_at = datetime.now().isoformat(timespec="seconds")
    output_dir = Path(request.output_dir or tempfile.mkdtemp(prefix="wechat-collect-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    run_id = output_dir.name if output_dir.name else datetime.now().strftime("%Y%m%d-%H%M%S-wechat")
    conversations: list[dict[str, Any]] = []

    if request.mode == "recent_contacts":
        home_root = dump_provider(output_dir / "home.json")
        contacts = extract_contacts(home_root)[:request.max_contacts]
        for index, contact in enumerate(contacts, start=1):
            tap_contact(contact)
            chat_path = output_dir / f"chat_{index:02d}_{safe_filename(contact.name)}.json"
            chat_root = dump_provider(chat_path)
            swipe_history(chat_root, request)
            conversations.append(_conversation_from_chat_root(contact, chat_root, str(chat_path)))
            press_back()
    else:
        if gui_search(request.target_contact) is False:
            raise RuntimeError("指定联系人搜索失败")
        contact = Contact(request.target_contact, "", "", None, 0, 0, [request.target_contact])
        chat_path = output_dir / f"chat_01_{safe_filename(request.target_contact)}.json"
        chat_root = dump_provider(chat_path)
        swipe_history(chat_root, request)
        conversations.append(_conversation_from_chat_root(contact, chat_root, str(chat_path)))

    daily_entries = daily_log_entries_from_conversations(conversations, request.days)
    result = {
        "status": "ok",
        "message": f"collected {len(conversations)} conversations",
        "run_id": run_id,
        "started_at": started_at,
        "finished_at": datetime.now().isoformat(timespec="seconds"),
        "mode": request.mode,
        "days": request.days,
        "contacts_requested": request.max_contacts,
        "contacts_collected": len(conversations),
        "conversations": conversations,
        "daily_log_entries": daily_entries,
        "artifacts": {},
    }
    result["artifacts"] = _write_payloads(output_dir, result)
    return result
```

Replace the empty `collect_action` skeleton with:

```python
def collect_action(payload: dict[str, Any], hdc_prefix: str, gui_search: Callable[[str], Any]) -> dict[str, Any]:
    request = normalize_collect_request(payload)
    output_dir = Path(request.output_dir or tempfile.mkdtemp(prefix="wechat-collect-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    prefix = _split_hdc_prefix(hdc_prefix)

    def dump_provider(path: Path) -> dict[str, Any]:
        dump_path = dump_layout(path, hdc=prefix[0] if prefix else "hdc")
        return load_ui_tree(dump_path)

    def tap_contact(contact: Contact) -> None:
        tap(contact.tap_x, contact.tap_y, hdc=prefix[0] if prefix else "hdc")

    return collect_action_with_device(
        {**payload, "output_dir": str(output_dir)},
        dump_provider=dump_provider,
        tap_contact=tap_contact,
        press_back=lambda: press_back(hdc=prefix[0] if prefix else "hdc"),
        swipe_history=lambda root, req: None,
        gui_search=gui_search,
    )
```

This uses the parser and bridge contract with a minimal HDC adapter. A later hardening pass can replace the `prefix[0]` compatibility adapter with a list-based HDC runner across the copied collector functions.

- [ ] **Step 4: Run orchestration tests to verify they pass**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py
```

Expected: PASS.

- [ ] **Step 5: Commit orchestration**

Run:

```bash
git add -f entry/src/main/python/wechat_collect/service.py entry/src/main/python/test_wechat_collect.py
git commit -m "实现微信采集服务编排"
```

## Task 5: Add ArkTS Settings Types and Validation

**Files:**
- Create: `entry/src/main/ets/utils/wechat/WechatAutoSummaryTypes.ets`
- Create: `entry/src/test/WechatAutoSummaryUnit.test.ets`
- Modify: `entry/src/test/List.test.ets`

- [ ] **Step 1: Write failing ArkTS validation tests**

Create `entry/src/test/WechatAutoSummaryUnit.test.ets`:

```ts
import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
  DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
  WECHAT_AUTO_SUMMARY_MODE_RECENT,
  WECHAT_AUTO_SUMMARY_MODE_TARGET,
  normalizeWechatAutoSummaryDays,
  normalizeWechatAutoSummaryMaxContacts,
  normalizeWechatAutoSummaryMode,
  validateWechatAutoSummaryRequest,
  WechatAutoSummaryRequest
} from '../main/ets/utils/wechat/WechatAutoSummaryTypes';

export default function wechatAutoSummaryUnitTest() {
  describe('wechatAutoSummaryUnitTest', () => {
    it('normalizesDefaultRanges', 0, () => {
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_DAYS).assertEqual('7');
      expect(DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS).assertEqual('10');
      expect(normalizeWechatAutoSummaryDays('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryDays('120')).assertEqual(90);
      expect(normalizeWechatAutoSummaryMaxContacts('0')).assertEqual(1);
      expect(normalizeWechatAutoSummaryMaxContacts('80')).assertEqual(50);
    });

    it('normalizesModes', 0, () => {
      expect(normalizeWechatAutoSummaryMode(WECHAT_AUTO_SUMMARY_MODE_TARGET)).assertEqual(WECHAT_AUTO_SUMMARY_MODE_TARGET);
      expect(normalizeWechatAutoSummaryMode('bad')).assertEqual(WECHAT_AUTO_SUMMARY_MODE_RECENT);
    });

    it('validatesTargetContactRequest', 0, () => {
      let request: WechatAutoSummaryRequest = {
        mode: WECHAT_AUTO_SUMMARY_MODE_TARGET,
        days: 7,
        max_contacts: 10,
        target_contact: '',
        swipe_speed: 2500,
        history_swipe_ratio: 0.65,
        stable_swipes: 3,
        max_history_swipes: 80,
        wait: 1.0
      };
      expect(validateWechatAutoSummaryRequest(request).length > 0).assertTrue();
      request.target_contact = '小赵';
      expect(validateWechatAutoSummaryRequest(request)).assertEqual('');
    });
  });
}
```

Add to `entry/src/test/List.test.ets`:

```ts
import wechatAutoSummaryUnitTest from './WechatAutoSummaryUnit.test';
```

and call it in `testsuite()`:

```ts
  wechatAutoSummaryUnitTest();
```

- [ ] **Step 2: Run ArkTS test to verify it fails**

Run:

```bash
env DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test --mode module -p module=entry@default -p product=default --no-daemon
```

Expected: FAIL because `WechatAutoSummaryTypes.ets` does not exist. If Hvigor hangs in the local sandbox, record the last printed stage and continue with static file checks.

- [ ] **Step 3: Implement ArkTS types and validation**

Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryTypes.ets`:

```ts
export const WECHAT_AUTO_SUMMARY_ENABLED_KEY: string = 'wechatAutoSummaryEnabled';
export const WECHAT_AUTO_SUMMARY_DEFAULT_DAYS_KEY: string = 'wechatAutoSummaryDefaultDays';
export const WECHAT_AUTO_SUMMARY_DEFAULT_MAX_CONTACTS_KEY: string = 'wechatAutoSummaryDefaultMaxContacts';
export const WECHAT_AUTO_SUMMARY_SWIPE_SPEED_KEY: string = 'wechatAutoSummarySwipeSpeed';
export const WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO_KEY: string = 'wechatAutoSummaryHistorySwipeRatio';
export const WECHAT_AUTO_SUMMARY_STABLE_SWIPES_KEY: string = 'wechatAutoSummaryStableSwipes';
export const WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES_KEY: string = 'wechatAutoSummaryMaxHistorySwipes';
export const WECHAT_AUTO_SUMMARY_WAIT_KEY: string = 'wechatAutoSummaryWait';

export const DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED: string = 'false';
export const DEFAULT_WECHAT_AUTO_SUMMARY_DAYS: string = '7';
export const DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS: string = '10';
export const DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED: string = '2500';
export const DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO: string = '0.65';
export const DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES: string = '3';
export const DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES: string = '80';
export const DEFAULT_WECHAT_AUTO_SUMMARY_WAIT: string = '1.0';

export const WECHAT_AUTO_SUMMARY_MODE_RECENT: string = 'recent_contacts';
export const WECHAT_AUTO_SUMMARY_MODE_TARGET: string = 'target_contact';

export interface WechatAutoSummaryRequest {
  mode: string;
  days: number;
  max_contacts: number;
  target_contact: string;
  swipe_speed: number;
  history_swipe_ratio: number;
  stable_swipes: number;
  max_history_swipes: number;
  wait: number;
}

export interface WechatAutoSummaryMessage {
  kind: string;
  text: string;
  sender?: string;
}

export interface WechatAutoSummaryConversation {
  title: string;
  contact?: Record<string, Object | string | number | boolean | null>;
  messages: WechatAutoSummaryMessage[];
}

export interface WechatAutoSummaryResponse {
  status: string;
  message?: string;
  run_id?: string;
  mode?: string;
  days?: number;
  contacts_requested?: number;
  contacts_collected?: number;
  conversations?: WechatAutoSummaryConversation[];
  daily_log_entries?: string[];
  artifacts?: Record<string, Object | string | number | boolean | null>;
}

function normalizeNumberText(value: string, fallback: number): number {
  let parsed = Number(value);
  return isNaN(parsed) ? fallback : parsed;
}

function clampNumber(value: number, minimum: number, maximum: number): number {
  return Math.max(minimum, Math.min(maximum, value));
}

export function normalizeWechatAutoSummaryDays(value: string): number {
  return Math.round(clampNumber(normalizeNumberText(value, Number(DEFAULT_WECHAT_AUTO_SUMMARY_DAYS)), 1, 90));
}

export function normalizeWechatAutoSummaryMaxContacts(value: string): number {
  return Math.round(clampNumber(normalizeNumberText(value, Number(DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS)), 1, 50));
}

export function normalizeWechatAutoSummaryMode(value: string): string {
  return value === WECHAT_AUTO_SUMMARY_MODE_TARGET ? WECHAT_AUTO_SUMMARY_MODE_TARGET : WECHAT_AUTO_SUMMARY_MODE_RECENT;
}

export function validateWechatAutoSummaryRequest(request: WechatAutoSummaryRequest): string {
  if (request.mode === WECHAT_AUTO_SUMMARY_MODE_TARGET && request.target_contact.trim().length === 0) {
    return '请输入联系人名称';
  }
  if (request.days < 1 || request.days > 90) {
    return '时间范围需在 1 到 90 天之间';
  }
  if (request.max_contacts < 1 || request.max_contacts > 50) {
    return '最近联系人数量需在 1 到 50 个之间';
  }
  return '';
}
```

- [ ] **Step 4: Run ArkTS tests**

Run the same Hvigor test command. Expected: PASS for `WechatAutoSummaryUnit.test` if Hvigor completes; if not, record the blocked stage.

- [ ] **Step 5: Commit types and tests**

Run:

```bash
git add -f entry/src/main/ets/utils/wechat/WechatAutoSummaryTypes.ets entry/src/test/WechatAutoSummaryUnit.test.ets entry/src/test/List.test.ets
git commit -m "新增微信汇总设置校验"
```

## Task 6: Add Settings UI and Settings Navigation

**Files:**
- Modify: `entry/src/main/ets/pages/settings/SettingsCenterPage.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`
- Modify: `entry/src/main/ets/pages/collection/CollectionPage.ets`

- [ ] **Step 1: Add settings persistent links**

In `Index.ets`, import constants from `WechatAutoSummaryTypes.ets` and register defaults near existing `PersistentStorage.persistProp` calls:

```ts
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_ENABLED_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_DEFAULT_DAYS_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_DAYS);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_DEFAULT_MAX_CONTACTS_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_SWIPE_SPEED_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_STABLE_SWIPES_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES);
PersistentStorage.persistProp(WECHAT_AUTO_SUMMARY_WAIT_KEY, DEFAULT_WECHAT_AUTO_SUMMARY_WAIT);
```

Add `@StorageLink` fields to `Index.ets` and `SettingsCenterPage.ets` for the same keys.

- [ ] **Step 2: Lift Settings section state**

In `Index.ets`, import `SETTINGS_SECTION_NONE` and `SettingsSectionId`, then add:

```ts
@State settingsSectionId: number = SETTINGS_SECTION_NONE;
```

In `SettingsCenterPage.ets`, replace:

```ts
@State selectedSectionId: number = SETTINGS_SECTION_NONE;
```

with:

```ts
@Link selectedSectionId: number;
```

When constructing `SettingsCenterPage` in `Index.ets`, pass:

```ts
selectedSectionId: $settingsSectionId,
```

- [ ] **Step 3: Wire “新增采集源” navigation**

In `CollectionPage.ets`, add callback:

```ts
onOpenDataCollectionSettings: () => void = () => {};
```

Replace the current toast click handler on “新增采集源”:

```ts
.onClick(() => { this.onOpenDataCollectionSettings(); })
```

In `Index.ets`, pass:

```ts
onOpenDataCollectionSettings: () => {
  this.settingsSectionId = SettingsSectionId.DataCollection;
  this.currentTab = MainTabIndex.Settings;
}
```

- [ ] **Step 4: Add WeChat settings controls**

In `SettingsCenterPage.ets`, import defaults and keys. Add `@StorageLink` fields:

```ts
@StorageLink('wechatAutoSummaryEnabled') wechatAutoSummaryEnabled: string = DEFAULT_WECHAT_AUTO_SUMMARY_ENABLED;
@StorageLink('wechatAutoSummaryDefaultDays') wechatAutoSummaryDefaultDays: string = DEFAULT_WECHAT_AUTO_SUMMARY_DAYS;
@StorageLink('wechatAutoSummaryDefaultMaxContacts') wechatAutoSummaryDefaultMaxContacts: string = DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS;
@StorageLink('wechatAutoSummarySwipeSpeed') wechatAutoSummarySwipeSpeed: string = DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED;
@StorageLink('wechatAutoSummaryHistorySwipeRatio') wechatAutoSummaryHistorySwipeRatio: string = DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO;
@StorageLink('wechatAutoSummaryStableSwipes') wechatAutoSummaryStableSwipes: string = DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES;
@StorageLink('wechatAutoSummaryMaxHistorySwipes') wechatAutoSummaryMaxHistorySwipes: string = DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES;
@StorageLink('wechatAutoSummaryWait') wechatAutoSummaryWait: string = DEFAULT_WECHAT_AUTO_SUMMARY_WAIT;
@State wechatAutoSummaryAdvancedOpen: boolean = false;
```

At the top of `DataCollectionSection()`, insert:

```ts
this.SettingToggle('微信消息自动汇总', '开启后在汇总页显示微信采集卡片，并保存原始 JSON/Markdown', this.wechatAutoSummaryEnabled === 'true',
  (value: boolean) => { this.wechatAutoSummaryEnabled = value ? 'true' : 'false'; })
if (this.wechatAutoSummaryEnabled === 'true') {
  this.SettingInput('微信默认时间范围（天）', this.wechatAutoSummaryDefaultDays, DEFAULT_WECHAT_AUTO_SUMMARY_DAYS,
    (value: string) => { this.wechatAutoSummaryDefaultDays = String(normalizeWechatAutoSummaryDays(value)); })
  this.SettingInput('微信默认最近联系人数量', this.wechatAutoSummaryDefaultMaxContacts, DEFAULT_WECHAT_AUTO_SUMMARY_MAX_CONTACTS,
    (value: string) => { this.wechatAutoSummaryDefaultMaxContacts = String(normalizeWechatAutoSummaryMaxContacts(value)); })
  Text('将保存微信原始消息 JSON/Markdown，并生成联系人级 daily-log。')
    .fontSize(12)
    .fontColor('#D26B31')
    .width('100%')
    .margin({ top: 8, bottom: 8 })
  Text(this.wechatAutoSummaryAdvancedOpen ? '收起微信高级参数' : '展开微信高级参数')
    .fontSize(13)
    .fontColor('#4F68FF')
    .width('100%')
    .margin({ top: 8, bottom: 4 })
    .onClick(() => { this.wechatAutoSummaryAdvancedOpen = !this.wechatAutoSummaryAdvancedOpen; })
  if (this.wechatAutoSummaryAdvancedOpen) {
    this.SettingInput('滑动速度', this.wechatAutoSummarySwipeSpeed, DEFAULT_WECHAT_AUTO_SUMMARY_SWIPE_SPEED,
      (value: string) => { this.wechatAutoSummarySwipeSpeed = value; })
    this.SettingInput('历史滑动距离比例', this.wechatAutoSummaryHistorySwipeRatio, DEFAULT_WECHAT_AUTO_SUMMARY_HISTORY_SWIPE_RATIO,
      (value: string) => { this.wechatAutoSummaryHistorySwipeRatio = value; })
    this.SettingInput('稳定停止次数', this.wechatAutoSummaryStableSwipes, DEFAULT_WECHAT_AUTO_SUMMARY_STABLE_SWIPES,
      (value: string) => { this.wechatAutoSummaryStableSwipes = value; })
    this.SettingInput('最大历史滑动次数', this.wechatAutoSummaryMaxHistorySwipes, DEFAULT_WECHAT_AUTO_SUMMARY_MAX_HISTORY_SWIPES,
      (value: string) => { this.wechatAutoSummaryMaxHistorySwipes = value; })
    this.SettingInput('导航等待秒数', this.wechatAutoSummaryWait, DEFAULT_WECHAT_AUTO_SUMMARY_WAIT,
      (value: string) => { this.wechatAutoSummaryWait = value; })
  }
}
```

- [ ] **Step 5: Run static checks**

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Commit settings UI**

Run:

```bash
git add -f entry/src/main/ets/pages/settings/SettingsCenterPage.ets entry/src/main/ets/pages/Index.ets entry/src/main/ets/pages/collection/CollectionPage.ets
git commit -m "接入微信汇总采集源设置"
```

## Task 7: Add ArkTS HDC Client and Storage Writer

**Files:**
- Create: `entry/src/main/ets/utils/wechat/WechatAutoSummaryClient.ets`
- Create: `entry/src/main/ets/utils/wechat/WechatAutoSummaryStorage.ets`
- Modify: `entry/src/test/WechatAutoSummaryUnit.test.ets`

- [ ] **Step 1: Add failing storage tests**

Append to `entry/src/test/WechatAutoSummaryUnit.test.ets`:

```ts
import {
  renderWechatAutoSummaryDailyLog,
  wechatAutoSummaryRunDir
} from '../main/ets/utils/wechat/WechatAutoSummaryStorage';

// inside describe()
    it('rendersDailyLogWithMetadataAndEntries', 0, () => {
      let content = renderWechatAutoSummaryDailyLog('run-1', 'recent_contacts', 7, [
        '微信联系人「小赵」最近 7 天消息采集。完整消息摘录：\n- 我：买手机'
      ]);
      expect(content.indexOf('DAILY_LOG_METADATA') >= 0).assertTrue();
      expect(content.indexOf('"task_scene_id":3') >= 0 || content.indexOf('"task_scene_id": 3') >= 0).assertTrue();
      expect(content.indexOf('1. 微信联系人「小赵」最近 7 天消息采集') >= 0).assertTrue();
    });

    it('usesWechatRunDirectoryUnderWorkflows', 0, () => {
      expect(wechatAutoSummaryRunDir('/tmp/files', 'run-1')).assertEqual('/tmp/files/workflows/wechat-collection/runs/run-1');
    });
```

- [ ] **Step 2: Run ArkTS test to verify it fails**

Run the Hvigor test command from Task 5. Expected: FAIL because `WechatAutoSummaryStorage.ets` does not exist.

- [ ] **Step 3: Implement storage writer**

Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryStorage.ets`:

```ts
import { JSON as ArkJSON } from '@kit.ArkTS';
import { DataManagerStorage } from '../../datamanager/DataManagerStorage';

interface DailyLogMetadataPayload {
  workflow_metadata: Record<string, Object | string | number | boolean | null>;
  latest_entry_index: number;
}

export function wechatAutoSummaryRunDir(filesDir: string, runId: string): string {
  let storage = new DataManagerStorage();
  return storage.join(filesDir, 'workflows', 'wechat-collection', 'runs', runId);
}

export function renderWechatAutoSummaryDailyLog(runId: string, mode: string, days: number, entries: string[]): string {
  let workflowMetadata: Record<string, Object | string | number | boolean | null> = {};
  workflowMetadata['task_scene_id'] = 3;
  workflowMetadata['source_app'] = 'wechat';
  workflowMetadata['collector'] = 'wechat_auto_summary';
  workflowMetadata['run_id'] = runId;
  workflowMetadata['mode'] = mode;
  workflowMetadata['days'] = days;
  let metadata: DailyLogMetadataPayload = {
    workflow_metadata: workflowMetadata,
    latest_entry_index: entries.length
  };
  let body = entries.map((entry: string, index: number): string => {
    return String(index + 1) + '. ' + entry.trim();
  }).join('\n\n');
  return '<!-- DAILY_LOG_METADATA\n' + ArkJSON.stringify(metadata, null, 2) + '\n-->\n\n' + body + '\n';
}

export class WechatAutoSummaryStorage {
  private storage: DataManagerStorage = new DataManagerStorage();
  private filesDir: string;

  constructor(filesDir: string) {
    this.filesDir = filesDir;
  }

  writeRawArtifact(runId: string, name: string, content: string): string {
    let path = this.storage.join(wechatAutoSummaryRunDir(this.filesDir, runId), name);
    this.storage.writeTextAtomic(path, content);
    return path;
  }

  writeDailyLog(runId: string, mode: string, days: number, dateKey: string, entries: string[]): string {
    let fileName = 'com.tencent.mm__wechat_auto_summary__' + runId + '.md';
    let path = this.storage.join(this.filesDir, 'workflows', 'daily-log', dateKey, fileName);
    this.storage.writeTextAtomic(path, renderWechatAutoSummaryDailyLog(runId, mode, days, entries));
    return path;
  }
}
```

- [ ] **Step 4: Implement HDC client**

Create `entry/src/main/ets/utils/wechat/WechatAutoSummaryClient.ets`:

```ts
import { http } from '@kit.NetworkKit';
import { JSON as ArkJSON } from '@kit.ArkTS';
import { WechatAutoSummaryRequest, WechatAutoSummaryResponse } from './WechatAutoSummaryTypes';

interface WorkflowRequest {
  action: string;
  payload: Object;
}

export class WechatAutoSummaryClient {
  private baseUrl: string;

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl;
  }

  private workflowUrl(): string {
    let url = this.baseUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url + '/api/workflow';
  }

  async collect(request: WechatAutoSummaryRequest): Promise<WechatAutoSummaryResponse> {
    let httpReq = http.createHttp();
    try {
      let body: WorkflowRequest = {
        action: 'wechat_collect',
        payload: request as Object
      };
      let response = await httpReq.request(this.workflowUrl(), {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: ArkJSON.stringify(body),
        connectTimeout: 8000,
        readTimeout: 300000,
        expectDataType: http.HttpDataType.STRING
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        return {
          status: 'error',
          message: 'HDC bridge HTTP ' + response.responseCode + ': ' + String(response.result)
        };
      }
      return ArkJSON.parse(response.result as string) as WechatAutoSummaryResponse;
    } catch (e) {
      let err = e as Error;
      return {
        status: 'error',
        message: err.message
      };
    } finally {
      httpReq.destroy();
    }
  }
}
```

- [ ] **Step 5: Run tests/checks**

Run:

```bash
git diff --check
```

Run Hvigor test command. Expected: storage tests pass if Hvigor completes.

- [ ] **Step 6: Commit client and storage**

Run:

```bash
git add -f entry/src/main/ets/utils/wechat/WechatAutoSummaryClient.ets entry/src/main/ets/utils/wechat/WechatAutoSummaryStorage.ets entry/src/test/WechatAutoSummaryUnit.test.ets
git commit -m "新增微信汇总客户端和存储"
```

## Task 8: Add Summary Page WeChat Card and Run Orchestration

**Files:**
- Modify: `entry/src/main/ets/pages/collection/CollectionPage.ets`
- Modify: `entry/src/main/ets/pages/Index.ets`

- [ ] **Step 1: Add CollectionPage props and local state**

In `CollectionPage.ets`, import request constants and add:

```ts
@Prop wechatAutoSummaryEnabled: boolean = false;
@Prop wechatAutoSummaryDefaultDays: string = '7';
@Prop wechatAutoSummaryDefaultMaxContacts: string = '10';
@Prop wechatAutoSummaryRunning: boolean = false;
@Prop wechatAutoSummaryStatus: string = '';
onRunWechatAutoSummary: (request: WechatAutoSummaryRequest) => Promise<void> = async (request: WechatAutoSummaryRequest) => {};
@State private wechatMode: string = WECHAT_AUTO_SUMMARY_MODE_RECENT;
@State private wechatDaysInput: string = '';
@State private wechatMaxContactsInput: string = '';
@State private wechatTargetContactInput: string = '';
```

Add helper:

```ts
private buildWechatRequest(): WechatAutoSummaryRequest {
  let daysText = this.wechatDaysInput.length > 0 ? this.wechatDaysInput : this.wechatAutoSummaryDefaultDays;
  let maxContactsText = this.wechatMaxContactsInput.length > 0 ? this.wechatMaxContactsInput : this.wechatAutoSummaryDefaultMaxContacts;
  return {
    mode: normalizeWechatAutoSummaryMode(this.wechatMode),
    days: normalizeWechatAutoSummaryDays(daysText),
    max_contacts: normalizeWechatAutoSummaryMaxContacts(maxContactsText),
    target_contact: this.wechatTargetContactInput.trim(),
    swipe_speed: 2500,
    history_swipe_ratio: 0.65,
    stable_swipes: 3,
    max_history_swipes: 80,
    wait: 1.0
  };
}
```

- [ ] **Step 2: Add WeChat card builder**

Add a `WechatAutoSummaryCard()` builder near the existing button builders:

```ts
@Builder WechatAutoSummaryCard() {
  if (this.wechatAutoSummaryEnabled) {
    Column() {
      Text('微信消息自动汇总').fontSize(17).fontWeight(FontWeight.Bold).fontColor('#151A28').width('100%')
      Text('采集微信会话并写入联系人级 daily-log').fontSize(12).fontColor('#6F7684').width('100%').margin({ top: 4 })
      Row() {
        Button('最近联系人')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_RECENT ? Color.White : '#4F68FF')
          .backgroundColor(this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_RECENT ? '#4F68FF' : '#EEF3FF')
          .borderRadius(10)
          .onClick(() => { this.wechatMode = WECHAT_AUTO_SUMMARY_MODE_RECENT; })
        Button('指定联系人')
          .height(34)
          .layoutWeight(1)
          .fontSize(12)
          .fontColor(this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_TARGET ? Color.White : '#4F68FF')
          .backgroundColor(this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_TARGET ? '#4F68FF' : '#EEF3FF')
          .borderRadius(10)
          .margin({ left: 8 })
          .onClick(() => { this.wechatMode = WECHAT_AUTO_SUMMARY_MODE_TARGET; })
      }.width('100%').margin({ top: 14 })
      TextInput({ placeholder: '时间范围（天），默认 ' + this.wechatAutoSummaryDefaultDays, text: this.wechatDaysInput })
        .height(40).width('100%').fontSize(13).backgroundColor('#F2F5FC').borderRadius(12).margin({ top: 10 })
        .onChange((value: string) => { this.wechatDaysInput = value; })
      TextInput({ placeholder: '最近联系人数量，默认 ' + this.wechatAutoSummaryDefaultMaxContacts, text: this.wechatMaxContactsInput })
        .height(40).width('100%').fontSize(13).backgroundColor('#F2F5FC').borderRadius(12).margin({ top: 10 })
        .onChange((value: string) => { this.wechatMaxContactsInput = value; })
      if (this.wechatMode === WECHAT_AUTO_SUMMARY_MODE_TARGET) {
        TextInput({ placeholder: '联系人名称', text: this.wechatTargetContactInput })
          .height(40).width('100%').fontSize(13).backgroundColor('#F2F5FC').borderRadius(12).margin({ top: 10 })
          .onChange((value: string) => { this.wechatTargetContactInput = value; })
      }
      Button(this.wechatAutoSummaryRunning ? '采集中' : '开始采集')
        .height(42)
        .width('100%')
        .fontSize(14)
        .fontColor(Color.White)
        .backgroundColor(this.wechatAutoSummaryRunning ? '#8A92A3' : '#2D9B73')
        .borderRadius(12)
        .enabled(!this.wechatAutoSummaryRunning)
        .margin({ top: 12 })
        .onClick(async () => {
          let request = this.buildWechatRequest();
          let error = validateWechatAutoSummaryRequest(request);
          if (error.length > 0) {
            promptAction.showToast({ message: error, duration: 1500 });
            return;
          }
          await this.onRunWechatAutoSummary(request);
        })
      if (this.wechatAutoSummaryStatus.length > 0) {
        Text(this.wechatAutoSummaryStatus).fontSize(12).fontColor('#6F7684').width('100%').margin({ top: 8 })
      }
    }
    .width('86%')
    .padding(18)
    .backgroundColor('#F9FBFF')
    .borderRadius(16)
    .margin({ top: COLLECTION_SECTION_GAP })
  }
}
```

Call `this.WechatAutoSummaryCard()` above the “新增采集源” card.

- [ ] **Step 3: Add Index orchestration state and method**

In `Index.ets`, add:

```ts
@State wechatAutoSummaryRunning: boolean = false;
@State wechatAutoSummaryStatus: string = '';
```

Add method:

```ts
private async runWechatAutoSummary(request: WechatAutoSummaryRequest): Promise<void> {
  if (this.hdcServerIp.trim().length === 0) {
    showToastSafely('请先配置 HDC Server', 1500);
    return;
  }
  this.wechatAutoSummaryRunning = true;
  this.wechatAutoSummaryStatus = '正在采集微信消息';
  try {
    let client = new WechatAutoSummaryClient(this.hdcServerIp);
    let response = await client.collect(request);
    if (response.status !== 'ok') {
      throw new Error(response.message || '微信采集失败');
    }
    let runId = response.run_id && response.run_id.length > 0 ? response.run_id : this.currentLocalDateKey() + '-wechat';
    let storage = new WechatAutoSummaryStorage(this.filesDir);
    storage.writeRawArtifact(runId, 'wechat_collect_response.json', ArkJSON.stringify(response, null, 2));
    let dailyEntries = response.daily_log_entries || [];
    if (dailyEntries.length > 0) {
      storage.writeDailyLog(runId, response.mode || request.mode, response.days || request.days, this.currentLocalDateKey(), dailyEntries);
    }
    this.wechatAutoSummaryStatus = '采集完成：' + String(response.contacts_collected || 0) + ' 个联系人';
    showToastSafely('微信采集完成，可点击同步整理', 1800);
  } catch (e) {
    let err = e as Error;
    this.wechatAutoSummaryStatus = '采集失败：' + err.message;
    showToastSafely('微信采集失败：' + err.message, 2200);
  } finally {
    this.wechatAutoSummaryRunning = false;
  }
}
```

Pass props to `CollectionPage`:

```ts
wechatAutoSummaryEnabled: this.wechatAutoSummaryEnabled === 'true',
wechatAutoSummaryDefaultDays: this.wechatAutoSummaryDefaultDays,
wechatAutoSummaryDefaultMaxContacts: this.wechatAutoSummaryDefaultMaxContacts,
wechatAutoSummaryRunning: this.wechatAutoSummaryRunning,
wechatAutoSummaryStatus: this.wechatAutoSummaryStatus,
onRunWechatAutoSummary: async (request: WechatAutoSummaryRequest) => { await this.runWechatAutoSummary(request); }
```

- [ ] **Step 4: Run checks**

Run:

```bash
git diff --check
```

Run Hvigor test command if available. Expected: no type/import errors if the build completes.

- [ ] **Step 5: Commit summary card and orchestration**

Run:

```bash
git add -f entry/src/main/ets/pages/collection/CollectionPage.ets entry/src/main/ets/pages/Index.ets
git commit -m "接入汇总页微信采集卡片"
```

## Task 9: Final Verification and Documentation Pass

**Files:**
- Modify if needed: `README.md`
- Modify if needed: `docs/superpowers/specs/2026-06-11-wechat-auto-summary-design.md`

- [ ] **Step 1: Run Python tests**

Run:

```bash
PYTHONPATH=entry/src/main/python python3 -B -m unittest entry/src/main/python/test_wechat_collect.py entry/src/main/python/test_hdc_server_workflow.py
```

Expected: PASS.

- [ ] **Step 2: Run ArkTS checks**

Run:

```bash
git diff --check
```

Expected: no output.

Run:

```bash
env DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test --mode module -p module=entry@default -p product=default --no-daemon
```

Expected: PASS, or record the exact stage/error if the local Hvigor process hangs or fails due to environment constraints.

- [ ] **Step 3: Run entry HAP build when local environment allows**

Run:

```bash
env DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:$PATH /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js --mode module -p module=entry@default -p product=default -p requiredDeviceType=phone assembleHap --analyze=normal --parallel --incremental --no-daemon
```

Expected: PASS, or record the exact stage/error if signing, sandboxing, or DevEco environment blocks the build.

- [ ] **Step 4: Manual device smoke test**

Use a real HarmonyOS device with WeChat logged in and `hdc list targets` working:

```bash
python3 entry/src/main/python/hdc_server.py
```

Verify:

- Settings > Data Collection shows “微信消息自动汇总”.
- Summary > “新增采集源” opens Settings > Data Collection.
- Switch on WeChat auto summary.
- Summary shows the WeChat collection card.
- Recent contacts mode collects at least one conversation and writes `wechat_collect_response.json`.
- Daily-log file appears under `workflows/daily-log/YYYY-MM-DD/`.
- Clicking Sync moves the contact-level entry into “汇总 > 聊天”.

- [ ] **Step 5: Commit verification/docs updates**

If README or spec notes were updated, run:

```bash
git add -f README.md docs/superpowers/specs/2026-06-11-wechat-auto-summary-design.md
git commit -m "补充微信汇总验证说明"
```

If no docs changed, skip this commit and report the verification results.

## Self-Review

**Spec coverage:**

- Settings switch and configurable defaults: Task 5 and Task 6.
- Summary page module and “新增采集源” navigation: Task 6 and Task 8.
- Independent Python module migrated from AUTOwechat: Task 1 and Task 2.
- `hdc_server.py` `uidump` and `wechat_collect` actions: Task 3.
- Recent contacts and target contact flows: Task 2, Task 4, and Task 9 manual verification.
- Raw artifacts and daily-log entries: Task 4, Task 7, and Task 8.
- Error handling and parameter validation: Task 2, Task 3, Task 5, and Task 8.
- Verification: Task 9.

**Placeholder scan:** This plan contains no deferred implementation slots. The one intentionally empty collection result in Task 3 is replaced by Task 4 before App integration begins, and Task 3 states the exact temporary behavior.

**Type consistency:** ArkTS request fields use `mode`, `days`, `max_contacts`, `target_contact`, `swipe_speed`, `history_swipe_ratio`, `stable_swipes`, `max_history_swipes`, and `wait` consistently across settings, CollectionPage, client, and Python request validation.
