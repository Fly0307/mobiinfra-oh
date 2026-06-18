"""微信 UI dump 采集命令行入口。"""

from __future__ import annotations

import argparse
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from .device import CollectOptions, collect_visible_chats, normalize_swipe_speed
from .parser import (
    DEFAULT_HISTORY_SWIPE_RATIO,
    DEFAULT_SWIPE_SPEED,
    build_chat_payload,
    extract_contacts,
    load_ui_tree,
)
from .render import print_json, print_json_and_markdown


def parse_contacts_command(args: argparse.Namespace) -> None:
    """CLI 子命令：解析首页 dump 中的联系人。"""

    root = load_ui_tree(args.dump)
    print_json([asdict(contact) for contact in extract_contacts(root)], args.output)


def parse_chat_command(args: argparse.Namespace) -> None:
    """CLI 子命令：解析单个聊天页 dump 中的消息。"""

    root = load_ui_tree(args.dump)
    print_json(build_chat_payload(root), args.output)


def collect_command(args: argparse.Namespace) -> None:
    """CLI 子命令：从设备当前微信首页进入联系人并采集消息。"""

    options = CollectOptions(
        dump_dir=args.dump_dir,
        hdc=args.hdc,
        remote_path=args.remote_path,
        wait=args.wait,
        max_contacts=args.max_contacts,
        target=args.target,
        days=args.days,
        max_history_swipes=args.max_history_swipes,
        stable_swipes=args.stable_swipes,
        swipe_wait=args.swipe_wait,
        swipe_speed=normalize_swipe_speed(args.swipe_speed),
        history_swipe=parse_swipe(args.history_swipe),
        history_swipe_ratio=args.history_swipe_ratio,
        reference_now=parse_reference_now(args.now),
        start_command=args.start_command,
        back_command=args.back_command,
    )

    def write_update(payload: dict[str, Any], conversation: dict[str, Any] | None, chat_dump: Path | None) -> None:
        if conversation is not None and chat_dump is not None:
            print_json_and_markdown(conversation, chat_dump.with_suffix(".messages.json"))
        print_json_and_markdown(payload, args.output)

    collect_visible_chats(options, on_update=write_update)


def parse_reference_now(value: str | None) -> datetime:
    """解析 `--now` 参数；为空时使用本机当前时间。"""

    if not value:
        return datetime.now()
    try:
        return datetime.fromisoformat(value)
    except ValueError as exc:
        raise ValueError("--now must be an ISO date or datetime, for example 2026-06-11T12:00:00") from exc


def parse_swipe(value: str | None) -> tuple[int, int, int, int] | None:
    """解析 `--history-swipe x1,y1,x2,y2` 参数。"""

    if not value:
        return None
    parts = [part.strip() for part in value.split(",")]
    if len(parts) != 4:
        raise ValueError("--history-swipe must use the format x1,y1,x2,y2")
    return tuple(int(part) for part in parts)  # type: ignore[return-value]


def build_parser() -> argparse.ArgumentParser:
    """构建命令行参数解析器。"""

    parser = argparse.ArgumentParser(
        description="Parse HarmonyOS WeChat uitest dumps or collect visible chats through hdc."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    contacts_parser = subparsers.add_parser("contacts", help="Extract visible contacts from a home dump.")
    contacts_parser.add_argument("dump", help="Path to a home-page ui_tree.json dump.")
    contacts_parser.add_argument("-o", "--output", help="Write JSON to this path instead of stdout.")
    contacts_parser.set_defaults(func=parse_contacts_command)

    chat_parser = subparsers.add_parser("chat", help="Extract visible messages from a chat dump.")
    chat_parser.add_argument("dump", help="Path to a chat-page ui_tree.json dump.")
    chat_parser.add_argument("-o", "--output", help="Write JSON to this path instead of stdout.")
    chat_parser.set_defaults(func=parse_chat_command)

    collect_parser = subparsers.add_parser(
        "collect", help="Dump the current WeChat home page, enter each visible contact, and extract messages."
    )
    collect_parser.add_argument("-o", "--output", default="wechat_messages.json", help="Output JSON path.")
    collect_parser.add_argument(
        "--dump-dir",
        default="dumps",
        help="Directory for raw page dumps; per-chat extracted .messages.json files are saved next to them.",
    )
    collect_parser.add_argument("--hdc", default="hdc", help="hdc executable path.")
    collect_parser.add_argument("--remote-path", default="/data/local/tmp/ui_tree.json")
    collect_parser.add_argument("--wait", type=float, default=1.0, help="Seconds to wait after navigation.")
    collect_parser.add_argument("--max-contacts", type=int, help="Only visit this many visible contacts.")
    collect_parser.add_argument("--target", help="Only collect the contact whose name exactly or partially matches this text.")
    collect_parser.add_argument("--days", type=int, help="Collect messages from the last N days for selected chats.")
    collect_parser.add_argument("--max-history-swipes", type=int, default=80, help="Maximum swipes toward older chat history.")
    collect_parser.add_argument(
        "--stable-swipes",
        type=int,
        default=3,
        help="Stop history search after this many consecutive unchanged pages.",
    )
    collect_parser.add_argument(
        "--swipe-wait",
        type=float,
        default=None,
        help="Seconds to wait after each history swipe. If omitted, dump immediately after swiping.",
    )
    collect_parser.add_argument(
        "--swipe-speed",
        type=int,
        default=DEFAULT_SWIPE_SPEED,
        help=(
            "Speed argument appended to hdc uiInput swipe; larger values swipe faster. "
            f"Use 0 to omit it. Default: {DEFAULT_SWIPE_SPEED}."
        ),
    )
    collect_parser.add_argument(
        "--history-swipe",
        help="History swipe coordinates as x1,y1,x2,y2. Overrides ratio-based swipe calculation.",
    )
    collect_parser.add_argument(
        "--history-swipe-ratio",
        type=float,
        default=DEFAULT_HISTORY_SWIPE_RATIO,
        help=f"Total history swipe distance as a ratio of page height. Default: {DEFAULT_HISTORY_SWIPE_RATIO}.",
    )
    collect_parser.add_argument(
        "--now",
        help="Reference current time for --days filtering, in ISO format. Defaults to the local current time.",
    )
    collect_parser.add_argument(
        "--start-command",
        help="Optional command to open WeChat before dumping, for example: hdc shell aa start ...",
    )
    collect_parser.add_argument(
        "--back-command",
        help="Optional command used to return from a chat page if the default Back key command differs.",
    )
    collect_parser.set_defaults(func=collect_command)

    return parser


def main(argv: list[str] | None = None) -> int:
    """命令行入口。

    参数 argv 主要用于测试；实际命令行运行时保持 None。
    """

    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
