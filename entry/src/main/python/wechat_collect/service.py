#!/usr/bin/env python3
"""微信采集服务层。

本模块面向 HTTP/HDC workflow bridge 集成，集中处理请求参数校验、UI dump
桥接动作、最近联系人滚动去重和 daily-log 文本生成。部分 workflow 动作会
执行受控 HDC 命令；其余采集逻辑通过调用方注入 dump 与滑动函数，便于单元测试
和后续接入不同服务入口。
"""

from __future__ import annotations

import math
import posixpath
import shlex
import subprocess
import tempfile
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from .parser import (
    Contact,
    build_chat_payload,
    extract_contacts,
    load_ui_tree,
    parse_chat_time,
    safe_filename,
)
from .render import markdown_path_for_json, print_json_and_markdown


DEFAULT_DAYS = 7
DEFAULT_MAX_CONTACTS = 10
DEFAULT_SWIPE_SPEED = 2500
DEFAULT_HISTORY_SWIPE_RATIO = 0.65
DEFAULT_STABLE_SWIPES = 3
DEFAULT_MAX_HISTORY_SWIPES = 80
DEFAULT_WAIT = 1.0
DEFAULT_MAX_LIST_SWIPES = 20
DEFAULT_HDC_TIMEOUT = 20

SUPPORTED_MODES = {"recent_contacts", "target_contact"}


@dataclass(frozen=True)
class WechatCollectRequest:
    """规范化后的微信采集请求参数。"""

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


def normalize_collect_request(payload: Any) -> WechatCollectRequest:
    """校验并规范化服务入口收到的微信采集请求。

    参数越界时会被夹到支持范围内；缺失参数使用默认值。入口 payload、
    字符串字段类型异常或非有限浮点数会抛出 ValueError，便于 HTTP 层统一返回错误。
    """

    if not isinstance(payload, dict):
        raise ValueError("request payload must be an object")

    mode = _stripped_string(payload.get("mode"), "recent_contacts", "mode")
    if mode not in SUPPORTED_MODES:
        raise ValueError(f"unsupported mode: {mode}")

    target_contact = _stripped_string(payload.get("target_contact"), "", "target_contact")
    if mode == "target_contact" and not target_contact:
        raise ValueError("target_contact is required for target_contact mode")

    return WechatCollectRequest(
        mode=mode,
        days=_clamp_int(payload.get("days"), DEFAULT_DAYS, 1, 90),
        max_contacts=_clamp_int(payload.get("max_contacts"), DEFAULT_MAX_CONTACTS, 1, 50),
        target_contact=target_contact,
        swipe_speed=_clamp_int(payload.get("swipe_speed"), DEFAULT_SWIPE_SPEED, 0, 20000),
        history_swipe_ratio=_clamp_float(
            payload.get("history_swipe_ratio"),
            DEFAULT_HISTORY_SWIPE_RATIO,
            0.1,
            0.95,
            "history_swipe_ratio",
        ),
        stable_swipes=_clamp_int(payload.get("stable_swipes"), DEFAULT_STABLE_SWIPES, 1, 10),
        max_history_swipes=_clamp_int(
            payload.get("max_history_swipes"),
            DEFAULT_MAX_HISTORY_SWIPES,
            1,
            300,
        ),
        wait=_clamp_float(payload.get("wait"), DEFAULT_WAIT, 0.0, 10.0, "wait"),
        max_list_swipes=_clamp_int(payload.get("max_list_swipes"), DEFAULT_MAX_LIST_SWIPES, 0, 100),
        output_dir=_stripped_string(payload.get("output_dir"), "", "output_dir"),
    )


def collect_recent_contacts_from_dumps(
    dump_provider: Callable[[], dict[str, Any]],
    swipe_next: Callable[[dict[str, Any]], None],
    max_contacts: int,
    stable_swipes: int,
    max_list_swipes: int,
) -> list[Contact]:
    """从多页微信首页 dump 中收集最近联系人。

    每轮先读取当前 dump 并提取联系人，按页面顺序把当前页所有未见过的
    联系人纳入结果。若数量不足且页面尚未稳定，会调用调用方注入的滑动
    函数，然后读取下一页 dump。
    """

    if max_contacts <= 0:
        return []

    contacts: list[Contact] = []
    seen_names: set[str] = set()
    previous_page_names: tuple[str, ...] | None = None
    stable_page_count = 0
    swipes_used = 0
    required_stable_pages = max(1, stable_swipes)
    allowed_swipes = max(0, max_list_swipes)

    while True:
        root = dump_provider()
        page_contacts = extract_contacts(root)
        page_names = tuple(contact.name.strip() for contact in page_contacts if contact.name.strip())

        for contact in page_contacts:
            name = contact.name.strip()
            if not name or name in seen_names:
                continue
            seen_names.add(name)
            contacts.append(contact)
            if len(contacts) >= max_contacts:
                return contacts

        if len(contacts) >= max_contacts:
            return contacts

        if previous_page_names is not None and page_names == previous_page_names:
            stable_page_count += 1
        else:
            stable_page_count = 0
        previous_page_names = page_names

        if stable_page_count >= required_stable_pages:
            return contacts
        if swipes_used >= allowed_swipes:
            return contacts

        swipe_next(root)
        swipes_used += 1


def daily_log_entries_from_conversations(conversations: list[dict[str, Any]], days: int) -> list[str]:
    """把会话采集结果转换为 Workflow daily-log 可写入的文本条目。"""

    entries: list[str] = []
    for conversation in conversations:
        contact_name = _conversation_contact_name(conversation)
        title = _conversation_title(conversation, contact_name)
        messages = _conversation_messages(conversation)
        message_count = sum(1 for message in messages if message.get("kind") == "message")
        visible_page_only = _conversation_is_visible_page_only(conversation)

        if visible_page_only:
            lines = [
                f"微信联系人「{contact_name}」当前可见页面消息采集",
                f"采集范围：请求最近 {days} 天，未展开历史",
                f"联系人：{contact_name}",
                f"会话标题：{title}",
            ]
        else:
            lines = [
                f"微信联系人「{contact_name}」最近 {days} 天消息采集",
                f"联系人：{contact_name}",
                f"会话标题：{title}",
            ]
        time_range = _format_time_range(conversation.get("time_range"))
        if time_range:
            lines.append(f"时间范围：{time_range}")
        lines.extend([f"消息数：{message_count}", "", "完整消息摘录："])

        excerpt_lines = [_format_message_line(message, contact_name) for message in messages]
        lines.extend(excerpt_lines or ["（无消息）"])
        entries.append("\n".join(lines).rstrip())

    return entries


def _split_hdc_prefix(hdc_prefix: str) -> list[str]:
    """把 HDC 前缀拆成 subprocess 参数，兼容 `hdc -t SERIAL`。"""

    text = str(hdc_prefix or "").strip()
    if not text:
        return ["hdc"]
    return shlex.split(text)


def uidump_action(payload: dict[str, Any], hdc_prefix: str) -> dict[str, Any]:
    """执行一次 UI dump 并把结果加载成 JSON 树返回给 workflow bridge。"""

    remote_path = _normalize_remote_dump_path(payload.get("remote_path"))
    output_dir = _resolve_output_dir(payload.get("output_dir"), "wechat-uidump-")

    prefix = _split_hdc_prefix(hdc_prefix)
    _run_hdc(prefix + ["shell", "uitest", "dumpLayout", "-p", remote_path])
    _run_hdc(prefix + ["file", "recv", remote_path, str(output_dir)])

    dump_path = output_dir / "ui_tree.json"
    received_path = output_dir / Path(remote_path).name
    if received_path.exists() and received_path != dump_path:
        received_path.replace(dump_path)
    if not dump_path.exists():
        raise RuntimeError(f"ui dump file not found: {dump_path}")

    return {
        "status": "ok",
        "message": "uidump ok",
        "dump_path": str(dump_path),
        "ui_tree": load_ui_tree(dump_path),
    }


def collect_action(
    payload: dict[str, Any],
    hdc_prefix: str,
    gui_search: Callable[[str], Any],
) -> dict[str, Any]:
    """通过 HDC 适配器执行微信采集服务编排。"""

    prefix = _split_hdc_prefix(hdc_prefix)
    remote_path = "/data/local/tmp/ui_tree.json"

    def dump_provider(path: Path) -> dict[str, Any]:
        path.parent.mkdir(parents=True, exist_ok=True)
        _run_hdc(prefix + ["shell", "uitest", "dumpLayout", "-p", remote_path])
        _run_hdc(prefix + ["file", "recv", remote_path, str(path.parent)])

        received_path = path.parent / Path(remote_path).name
        if received_path.exists() and received_path != path:
            received_path.replace(path)
        if not path.exists():
            raise RuntimeError(f"ui dump file not found: {path}")
        return load_ui_tree(path)

    def tap_contact(contact: Contact) -> None:
        _run_hdc(prefix + ["shell", "uiInput", "click", str(contact.tap_x), str(contact.tap_y)])

    def press_back() -> None:
        _run_hdc(prefix + ["shell", "uiInput", "keyEvent", "Back"])

    def swipe_contacts(root: dict[str, Any], request: WechatCollectRequest) -> None:
        command = [
            *prefix,
            "shell",
            "uitest",
            "uiInput",
            "swipe",
            "628",
            "2200",
            "628",
            "700",
        ]
        if request.swipe_speed > 0:
            command.append(str(request.swipe_speed))
        _run_hdc(command)

    return collect_action_with_device(
        payload,
        dump_provider=dump_provider,
        tap_contact=tap_contact,
        press_back=press_back,
        swipe_history=lambda chat_root, request: None,
        gui_search=gui_search,
        swipe_contacts=swipe_contacts,
    )


def collect_action_with_device(
    payload: dict[str, Any],
    dump_provider: Callable[[Path], dict[str, Any]],
    tap_contact: Callable[[Contact], None],
    press_back: Callable[[], None],
    swipe_history: Callable[[dict[str, Any], WechatCollectRequest], Any],
    gui_search: Callable[[str], Any],
    swipe_contacts: Callable[[dict[str, Any], WechatCollectRequest], Any] | None = None,
) -> dict[str, Any]:
    """使用注入的设备操作执行可测试的微信采集编排。

    该入口只负责编排首页 dump、联系人点击、聊天页 dump、导出文件和 daily-log
    生成。真实设备操作由调用方注入，单元测试可替换为假设备实现。
    """

    request = normalize_collect_request(payload)
    output_dir = _resolve_output_dir(request.output_dir, "wechat-collect-")

    started_at = datetime.now().replace(microsecond=0)
    run_id = output_dir.name or f"{started_at.strftime('%Y%m%dT%H%M%S')}-wechat"
    contacts_requested = 1 if request.mode == "target_contact" else request.max_contacts
    conversations: list[dict[str, Any]] = []
    home_dump = ""

    if request.mode == "recent_contacts":
        home_dump_index = 0
        home_dump_paths: list[str] = []

        def dump_home_page() -> dict[str, Any]:
            nonlocal home_dump_index
            home_dump_index += 1
            home_path = output_dir / ("home.json" if home_dump_index == 1 else f"home_{home_dump_index:02d}.json")
            home_dump_paths.append(str(home_path))
            return dump_provider(home_path)

        def swipe_home_list(root: dict[str, Any]) -> None:
            if swipe_contacts is not None:
                swipe_contacts(root, request)

        contacts = collect_recent_contacts_from_dumps(
            dump_home_page,
            swipe_home_list,
            max_contacts=request.max_contacts,
            stable_swipes=request.stable_swipes,
            max_list_swipes=request.max_list_swipes,
        )
        home_dump = home_dump_paths[0] if home_dump_paths else ""

        for index, contact in enumerate(contacts, start=1):
            tap_contact(contact)
            collection_error: BaseException | None = None
            try:
                chat_path = output_dir / f"chat_{index:02d}_{safe_filename(contact.name)}.json"
                chat_root = dump_provider(chat_path)
                updated_root = swipe_history(chat_root, request)
                if isinstance(updated_root, dict):
                    chat_root = updated_root
                conversations.append(_conversation_from_chat_root(contact, chat_root, str(chat_path)))
            except BaseException as exc:
                collection_error = exc
                raise
            finally:
                _press_back_after_tap(press_back, collection_error)
    else:
        search_result = gui_search(request.target_contact)
        if not _gui_search_succeeded(search_result):
            raise RuntimeError("指定联系人搜索失败")

        contact = Contact(
            name=request.target_contact,
            last_time="",
            preview="",
            bounds=None,
            tap_x=0,
            tap_y=0,
            raw_texts=[request.target_contact],
        )
        chat_path = output_dir / f"chat_01_{safe_filename(request.target_contact)}.json"
        collection_error: BaseException | None = None
        try:
            chat_root = dump_provider(chat_path)
            updated_root = swipe_history(chat_root, request)
            if isinstance(updated_root, dict):
                chat_root = updated_root
            conversations.append(_conversation_from_chat_root(contact, chat_root, str(chat_path)))
        except BaseException as exc:
            collection_error = exc
            raise
        finally:
            _press_back_after_tap(press_back, collection_error)

    daily_log_entries = daily_log_entries_from_conversations(conversations, request.days)
    finished_at = datetime.now().replace(microsecond=0)
    result = {
        "status": "ok",
        "message": f"collected {len(conversations)} conversations",
        "run_id": run_id,
        "started_at": started_at.isoformat(),
        "finished_at": finished_at.isoformat(),
        "mode": request.mode,
        "days": request.days,
        "target_contact": request.target_contact,
        "contacts_requested": contacts_requested,
        "contacts_collected": len(conversations),
        "conversations": conversations,
        "daily_log_entries": daily_log_entries,
        "artifacts": {
            "output_dir": str(output_dir),
            **_aggregate_artifact_paths(output_dir),
        },
        **({"home_dump": home_dump} if home_dump else {}),
    }
    result["artifacts"].update(_write_payloads(output_dir, result))
    return result


def _write_payloads(output_dir: Path, payload: dict[str, Any]) -> dict[str, str]:
    """写入聚合 JSON 与 Markdown，并返回产物路径。"""

    output_dir.mkdir(parents=True, exist_ok=True)
    json_path = output_dir / "wechat_collect.json"
    print_json_and_markdown(payload, json_path)
    markdown_path = markdown_path_for_json(json_path)
    return {
        "aggregate_json": str(json_path),
        "aggregate_markdown": str(markdown_path),
    }


def _conversation_from_chat_root(contact: Contact, root: dict[str, Any], dump_path: str) -> dict[str, Any]:
    """把单个聊天页 dump 转成统一会话记录。"""

    chat_payload = build_chat_payload(root, fallback_title=contact.name)
    messages = chat_payload["messages"]
    return {
        "contact": _serialize_contact(contact),
        "title": chat_payload["title"],
        "dump": dump_path,
        "snapshots": [dump_path],
        "messages": messages,
        "history_mode": "visible_page_only",
        "time_range": _messages_time_range(messages),
    }


def _serialize_contact(contact: Contact) -> dict[str, Any]:
    """转换联系人结构，保证内存结果与 JSON 产物的列表/字典形态一致。"""

    item = asdict(contact)
    bounds = item.get("bounds")
    if isinstance(bounds, tuple):
        item["bounds"] = list(bounds)
    return item


def _aggregate_artifact_paths(output_dir: Path) -> dict[str, str]:
    json_path = output_dir / "wechat_collect.json"
    return {
        "aggregate_json": str(json_path),
        "aggregate_markdown": str(markdown_path_for_json(json_path)),
    }


def _messages_time_range(messages: list[dict[str, Any]]) -> dict[str, str]:
    """从时间分隔消息中提取当前会话的可读时间范围。"""

    parsed_times = []
    reference = datetime.now()
    for message in messages:
        if message.get("kind") != "time":
            continue
        parsed = parse_chat_time(str(message.get("text") or ""), reference)
        if parsed is not None:
            parsed_times.append(parsed)

    if not parsed_times:
        return {"start": "", "end": "", "mode": "visible_page_only"}
    return {
        "start": min(parsed_times).isoformat(timespec="minutes"),
        "end": max(parsed_times).isoformat(timespec="minutes"),
        "mode": "visible_page_only",
    }


def _gui_search_succeeded(result: Any) -> bool:
    """判断 GUI 搜索是否成功；兼容旧的 True/None 与结构化返回值。"""

    if result is False:
        return False
    if isinstance(result, dict):
        return str(result.get("status") or "").strip().lower() == "ok"
    return True


def _press_back_after_tap(press_back: Callable[[], None], original_error: BaseException | None) -> None:
    """点击进入聊天后返回列表；返回失败时优先保留原始采集异常。"""

    try:
        press_back()
    except BaseException as back_error:
        if original_error is not None:
            back_error.__context__ = None
            original_error.__context__ = back_error
            return
        raise


def _normalize_remote_dump_path(value: Any) -> str:
    if value is None:
        text = "/data/local/tmp/ui_tree.json"
    elif isinstance(value, str):
        text = value.strip()
    else:
        raise ValueError("remote_path must be a string")

    if not text:
        text = "/data/local/tmp/ui_tree.json"
    normalized = posixpath.normpath(text)
    if not normalized.startswith("/data/local/tmp/"):
        raise ValueError("remote_path must stay under /data/local/tmp/")
    filename = posixpath.basename(normalized)
    if not filename or filename in (".", ".."):
        raise ValueError("remote_path must be a file path")
    if not filename.endswith(".json"):
        raise ValueError("remote_path must end with .json")
    return normalized


def _resolve_output_dir(value: Any, temp_prefix: str) -> Path:
    if value is None:
        path = Path(tempfile.mkdtemp(prefix=temp_prefix))
    elif isinstance(value, str):
        text = value.strip()
        path = Path(text).expanduser() if text else Path(tempfile.mkdtemp(prefix=temp_prefix))
    else:
        raise ValueError("output_dir must be a string")

    if path.exists() and not path.is_dir():
        raise ValueError(f"output_dir is not a directory: {path}")
    path.mkdir(parents=True, exist_ok=True)
    return path


def _run_hdc(args: list[str], timeout: int = DEFAULT_HDC_TIMEOUT) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired as ex:
        message = f"HDC command timed out after {timeout}s: {' '.join(args)}"
        raise RuntimeError(message) from ex
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or f"command failed: {' '.join(args)}"
        raise RuntimeError(message)
    return result


def _clamp_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        return default
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return min(max(parsed, minimum), maximum)


def _clamp_float(value: Any, default: float, minimum: float, maximum: float, field_name: str) -> float:
    if isinstance(value, bool):
        return default
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(parsed):
        raise ValueError(f"{field_name} must be finite")
    return min(max(parsed, minimum), maximum)


def _stripped_string(value: Any, default: str, field_name: str) -> str:
    if value is None:
        return default
    if not isinstance(value, str):
        raise ValueError(f"{field_name} must be a string")
    text = value.strip()
    return text if text else default


def _conversation_contact_name(conversation: dict[str, Any]) -> str:
    contact = conversation.get("contact")
    if isinstance(contact, dict):
        name = str(contact.get("name") or "").strip()
        if name:
            return name
    return _conversation_title(conversation, "未命名会话")


def _conversation_title(conversation: dict[str, Any], fallback: str) -> str:
    title = str(conversation.get("title") or "").strip()
    return title or fallback


def _conversation_messages(conversation: dict[str, Any]) -> list[dict[str, Any]]:
    messages = conversation.get("messages")
    if not isinstance(messages, list):
        return []
    return [message for message in messages if isinstance(message, dict)]


def _conversation_is_visible_page_only(conversation: dict[str, Any]) -> bool:
    if conversation.get("history_mode") == "visible_page_only":
        return True
    time_range = conversation.get("time_range")
    return isinstance(time_range, dict) and time_range.get("mode") == "visible_page_only"


def _format_time_range(value: Any) -> str:
    if isinstance(value, dict):
        start = str(value.get("start") or "").strip()
        end = str(value.get("end") or "").strip()
        if start and end:
            return f"{start} 至 {end}"
        return start or end
    if value is None:
        return ""
    return str(value).strip()


def _format_message_line(message: dict[str, Any], contact_name: str) -> str:
    text = str(message.get("text") or "")
    if message.get("kind") == "time":
        return text

    sender = _format_sender(message.get("sender"), contact_name)
    lines = text.splitlines() or [""]
    if len(lines) == 1:
        return f"{sender}：{lines[0]}"
    return "\n".join([f"{sender}：{lines[0]}", *[f"  {line}" for line in lines[1:]]])


def _format_sender(sender: Any, contact_name: str) -> str:
    sender_text = str(sender or "").strip()
    if sender_text == "self":
        return "我"
    if not sender_text or sender_text == "other":
        return contact_name
    return sender_text


__all__ = [
    "DEFAULT_DAYS",
    "DEFAULT_HISTORY_SWIPE_RATIO",
    "DEFAULT_MAX_CONTACTS",
    "DEFAULT_MAX_HISTORY_SWIPES",
    "DEFAULT_MAX_LIST_SWIPES",
    "DEFAULT_STABLE_SWIPES",
    "DEFAULT_SWIPE_SPEED",
    "DEFAULT_WAIT",
    "WechatCollectRequest",
    "collect_recent_contacts_from_dumps",
    "collect_action",
    "collect_action_with_device",
    "daily_log_entries_from_conversations",
    "normalize_collect_request",
    "uidump_action",
]
