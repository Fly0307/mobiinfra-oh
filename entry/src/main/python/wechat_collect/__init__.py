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
from .service import (
    WechatCollectRequest,
    collect_recent_contacts_from_dumps,
    daily_log_entries_from_conversations,
    normalize_collect_request,
)

__all__ = [
    "CollectOptions",
    "Contact",
    "HistorySnapshotOptions",
    "WechatCollectRequest",
    "build_chat_payload",
    "build_chat_payload_from_snapshots",
    "collect_recent_contacts_from_dumps",
    "compute_history_swipe",
    "daily_log_entries_from_conversations",
    "extract_chat_messages",
    "extract_chat_title",
    "extract_contacts",
    "normalize_collect_request",
    "parse_chat_time",
    "render_markdown",
]
