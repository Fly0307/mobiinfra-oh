#!/usr/bin/env python3
"""微信采集服务层。

本模块面向后续 HTTP/HDC 服务集成，集中处理请求参数校验、最近联系人
滚动去重和 daily-log 文本生成。这里不直接调用设备命令，调用方需要注入
dump 与滑动函数，便于单元测试和后续接入不同服务入口。
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from .parser import Contact, extract_contacts


DEFAULT_DAYS = 7
DEFAULT_MAX_CONTACTS = 10
DEFAULT_SWIPE_SPEED = 2500
DEFAULT_HISTORY_SWIPE_RATIO = 0.65
DEFAULT_STABLE_SWIPES = 3
DEFAULT_MAX_HISTORY_SWIPES = 80
DEFAULT_WAIT = 1.0
DEFAULT_MAX_LIST_SWIPES = 20

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


def normalize_collect_request(payload: dict[str, Any]) -> WechatCollectRequest:
    """校验并规范化服务入口收到的微信采集请求。

    参数越界时会被夹到支持范围内；缺失或类型异常时使用默认值。当前支持
    最近联系人批量采集和指定联系人采集两种模式。
    """

    mode = _stripped_string(payload.get("mode"), "recent_contacts")
    if mode not in SUPPORTED_MODES:
        raise ValueError(f"unsupported mode: {mode}")

    target_contact = _stripped_string(payload.get("target_contact"), "")
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
        ),
        stable_swipes=_clamp_int(payload.get("stable_swipes"), DEFAULT_STABLE_SWIPES, 1, 10),
        max_history_swipes=_clamp_int(
            payload.get("max_history_swipes"),
            DEFAULT_MAX_HISTORY_SWIPES,
            1,
            300,
        ),
        wait=_clamp_float(payload.get("wait"), DEFAULT_WAIT, 0.0, 10.0),
        max_list_swipes=_clamp_int(payload.get("max_list_swipes"), DEFAULT_MAX_LIST_SWIPES, 0, 100),
        output_dir=_stripped_string(payload.get("output_dir"), ""),
    )


def collect_recent_contacts_from_dumps(
    dump_provider: Callable[[], dict[str, Any]],
    swipe_next: Callable[[dict[str, Any]], None],
    max_contacts: int,
    stable_swipes: int,
    max_list_swipes: int,
) -> list[Contact]:
    """从多页微信首页 dump 中收集最近联系人。

    每轮先读取当前 dump 并提取联系人，再把当前页第一个未见过的联系人
    纳入结果。若数量不足且页面尚未稳定，会调用调用方注入的滑动函数，
    然后读取下一页 dump。
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
            break

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


def _clamp_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    if isinstance(value, bool):
        return default
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return default
    return min(max(parsed, minimum), maximum)


def _clamp_float(value: Any, default: float, minimum: float, maximum: float) -> float:
    if isinstance(value, bool):
        return default
    try:
        parsed = float(value)
    except (TypeError, ValueError):
        return default
    return min(max(parsed, minimum), maximum)


def _stripped_string(value: Any, default: str) -> str:
    if value is None:
        return default
    text = str(value).strip()
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
    "daily_log_entries_from_conversations",
    "normalize_collect_request",
]
