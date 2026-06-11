"""微信 UI dump 采集模块。"""

from .device import (
    CollectOptions,
    HistorySnapshotOptions,
)
from .parser import (
    Contact,
    build_chat_payload,
    build_chat_payload_from_snapshots,
    compute_history_swipe,
    extract_chat_messages,
    extract_chat_title,
    extract_contacts,
    parse_chat_time,
)
from .render import (
    render_markdown,
)

__all__ = [
    "CollectOptions",
    "Contact",
    "HistorySnapshotOptions",
    "build_chat_payload",
    "build_chat_payload_from_snapshots",
    "compute_history_swipe",
    "extract_chat_messages",
    "extract_chat_title",
    "extract_contacts",
    "parse_chat_time",
    "render_markdown",
]
