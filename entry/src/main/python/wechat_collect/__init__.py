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
