"""微信采集结果输出渲染工具。"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def print_json(payload: Any, output: str | None) -> None:
    """输出 JSON；output 为空时打印到 stdout。"""

    text = json.dumps(payload, ensure_ascii=False, indent=2)
    if output:
        Path(output).parent.mkdir(parents=True, exist_ok=True)
        Path(output).write_text(text + "\n", encoding="utf-8")
    else:
        print(text)


def print_json_and_markdown(payload: Any, output: str | Path | None) -> None:
    """同时写 JSON 和同名 Markdown。

    参数：
        payload: 聚合结果或单会话结果。
        output: JSON 输出路径；为空时只向 stdout 打印 JSON。
    """

    print_json(payload, str(output) if output is not None else None)
    if output is not None:
        print_markdown(payload, markdown_path_for_json(output))


def markdown_path_for_json(path: str | Path) -> Path:
    """把 JSON 输出路径转换为同名 Markdown 路径。"""

    output = Path(path)
    return output.with_suffix(".md") if output.suffix else output.with_name(output.name + ".md")


def print_markdown(payload: Any, output: str | Path) -> None:
    """把 payload 渲染为 Markdown 并写入文件。"""

    path = Path(output)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(render_markdown(payload) + "\n", encoding="utf-8")


def render_markdown(payload: Any) -> str:
    """把采集结果渲染成便于人工阅读的 Markdown 文本。

    payload 可以是聚合结果，也可以是单会话结果；函数会自动识别结构。
    """

    conversations = payload.get("conversations") if isinstance(payload, dict) else None
    if conversations is None and isinstance(payload, dict) and "messages" in payload:
        conversations = [payload]
    conversations = conversations or []

    lines = ["# 微信消息采集", ""]
    if isinstance(payload, dict) and payload.get("home_dump"):
        lines.extend([f"Home dump：`{payload['home_dump']}`", ""])

    for conversation in conversations:
        title = conversation.get("title") or conversation.get("contact", {}).get("name") or "未命名会话"
        contact_name = conversation.get("contact", {}).get("name", title)
        messages = conversation.get("messages") or []
        lines.extend(
            [
                f"## {title}",
                "",
                f"- 联系人：{contact_name}",
                f"- Dump：`{conversation.get('dump', '')}`",
                f"- 消息数：{len(messages)}",
            ]
        )
        snapshots = conversation.get("snapshots") or []
        if snapshots:
            lines.append("- 快照：")
            for snapshot in snapshots:
                lines.append(f"  - `{snapshot}`")
        lines.extend(["", "### 消息", ""])

        for message in messages:
            text = str(message.get("text") or "")
            if message.get("kind") == "time":
                lines.append(f"- {text}")
                continue

            sender = message.get("sender") or ""
            formatted = format_markdown_message_text(text)
            lines.append(f"- {sender}: {formatted}")

        lines.append("")

    return "\n".join(lines).rstrip()


def format_markdown_message_text(text: str) -> str:
    """格式化多行消息文本，让后续行保持在同一条 Markdown 列表项内。"""

    lines = text.splitlines() or [""]
    return "\n".join([lines[0], *[f"  {line}" for line in lines[1:]]])
