#!/usr/bin/env python3
"""从 HarmonyOS uitest dump 文件中提取微信联系人和聊天消息。"""

from __future__ import annotations

import argparse
import json
import re
import shlex
import subprocess
import time
from dataclasses import asdict, dataclass
from datetime import datetime, time as datetime_time, timedelta
from pathlib import Path
from typing import Any, Iterable


Bounds = tuple[int, int, int, int]

BOUNDS_RE = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")
TIME_OF_DAY_RE = re.compile(r"(上午|下午|晚上|凌晨|中午)?\s*(\d{1,2}):(\d{2})")
MONTH_DAY_RE = re.compile(r"(?:(\d{4})年)?(\d{1,2})月(\d{1,2})(?:日|号)?")
SLASH_DATE_RE = re.compile(r"(\d{1,2})/(\d{1,2})")
WEEKDAY_RE = re.compile(r"星期([一二三四五六日天])")
DEFAULT_HISTORY_SWIPE_RATIO = 0.65
DEFAULT_SWIPE_SPEED = 2500
BOUNDARY_OVERLAP_RATIO = 0.2


@dataclass(frozen=True)
class TextNode:
    """文本节点及其屏幕坐标。"""

    text: str
    bounds: Bounds | None


@dataclass(frozen=True)
class Contact:
    """首页会话列表中的一个联系人条目。"""

    name: str
    last_time: str
    preview: str
    bounds: Bounds | None
    tap_x: int
    tap_y: int
    raw_texts: list[str]


@dataclass(frozen=True)
class ChatEntry:
    """聊天页中的一条列表项，可能是时间分隔符或消息气泡。"""

    kind: str
    text: str
    sender: str | None
    bounds: Bounds | None
    text_bounds: Bounds | None
    image_bounds: list[Bounds]


def load_ui_tree(path: str | Path) -> dict[str, Any]:
    """读取 hdc dumpLayout 生成的 JSON UI 树。"""

    with Path(path).open("r", encoding="utf-8") as f:
        return json.load(f)


def parse_bounds(value: Any) -> Bounds | None:
    """解析 `[x1,y1][x2,y2]` 格式的 bounds 字符串。"""

    if not isinstance(value, str):
        return None
    match = BOUNDS_RE.fullmatch(value.strip())
    if not match:
        return None
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def bounds_center(bounds: Bounds | None) -> tuple[int, int]:
    """返回 bounds 中心点；没有坐标时返回 `(0, 0)`。"""

    if bounds is None:
        return 0, 0
    x1, y1, x2, y2 = bounds
    return (x1 + x2) // 2, (y1 + y2) // 2


def bounds_width(bounds: Bounds | None) -> int:
    """返回 bounds 宽度；没有坐标时返回 0。"""

    if bounds is None:
        return 0
    return max(0, bounds[2] - bounds[0])


def bounds_height(bounds: Bounds | None) -> int:
    """返回 bounds 高度；没有坐标时返回 0。"""

    if bounds is None:
        return 0
    return max(0, bounds[3] - bounds[1])


def attrs(node: dict[str, Any]) -> dict[str, Any]:
    """取节点 attributes，缺失或类型异常时返回空字典。"""

    node_attrs = node.get("attributes")
    return node_attrs if isinstance(node_attrs, dict) else {}


def children(node: dict[str, Any]) -> list[dict[str, Any]]:
    """取节点 children，仅保留字典类型的子节点。"""

    node_children = node.get("children")
    if not isinstance(node_children, list):
        return []
    return [child for child in node_children if isinstance(child, dict)]


def node_type(node: dict[str, Any]) -> str:
    """读取节点 type 字段。"""

    return str(attrs(node).get("type") or "")


def node_bounds(node: dict[str, Any]) -> Bounds | None:
    """读取节点坐标，优先使用 origBounds，回退到 bounds。"""

    node_attrs = attrs(node)
    return parse_bounds(node_attrs.get("origBounds")) or parse_bounds(node_attrs.get("bounds"))


def iter_nodes(node: dict[str, Any]) -> Iterable[dict[str, Any]]:
    """深度优先遍历 UI 树中的所有节点。"""

    yield node
    for child in children(node):
        yield from iter_nodes(child)


def iter_nodes_with_ancestors(
    node: dict[str, Any], ancestors: tuple[dict[str, Any], ...] = ()
) -> Iterable[tuple[dict[str, Any], tuple[dict[str, Any], ...]]]:
    """遍历节点并同时返回祖先链，用于排除特定容器内的文本。"""

    yield node, ancestors
    next_ancestors = ancestors + (node,)
    for child in children(node):
        yield from iter_nodes_with_ancestors(child, next_ancestors)


def direct_list_items(list_node: dict[str, Any]) -> list[dict[str, Any]]:
    """返回 List 节点的直接 ListItem 子节点。"""

    return [child for child in children(list_node) if node_type(child) == "ListItem"]


def find_list_nodes(root: dict[str, Any]) -> list[dict[str, Any]]:
    """找出页面内全部 List 节点。"""

    return [node for node in iter_nodes(root) if node_type(node) == "List"]


def find_best_list(root: dict[str, Any], *, prefer_scrollable: bool) -> dict[str, Any] | None:
    """选择最像主内容区的 List 节点。

    参数：
        root: 页面 UI 树根节点。
        prefer_scrollable: 为 True 时优先选择可滚动列表，适用于聊天页；
            为 False 时更偏向首页会话列表。
    """

    lists = find_list_nodes(root)
    if not lists:
        return None

    def score(list_node: dict[str, Any]) -> tuple[int, int, int]:
        is_scrollable = attrs(list_node).get("scrollable") == "true"
        scroll_score = 1 if prefer_scrollable and is_scrollable else 0
        item_count = len(direct_list_items(list_node))
        area = bounds_width(node_bounds(list_node)) * bounds_height(node_bounds(list_node))
        return scroll_score, item_count, area

    return max(lists, key=score)


def collect_text_nodes(node: dict[str, Any]) -> list[TextNode]:
    """收集某个节点下所有非空 Text 子节点，并按屏幕位置排序。"""

    text_nodes: list[TextNode] = []
    for candidate in iter_nodes(node):
        candidate_attrs = attrs(candidate)
        text = str(candidate_attrs.get("text") or "").strip()
        if node_type(candidate) == "Text" and text:
            text_nodes.append(TextNode(text=text, bounds=node_bounds(candidate)))
    return sorted(text_nodes, key=lambda item: _bounds_sort_key(item.bounds))


def collect_image_bounds(node: dict[str, Any]) -> list[Bounds]:
    """收集某个节点下所有 Image 节点的坐标。"""

    return [
        bounds
        for candidate in iter_nodes(node)
        if node_type(candidate) == "Image"
        for bounds in [node_bounds(candidate)]
        if bounds is not None
    ]


def _bounds_sort_key(bounds: Bounds | None) -> tuple[int, int]:
    if bounds is None:
        return 0, 0
    return bounds[1], bounds[0]


def extract_contacts(root: dict[str, Any]) -> list[Contact]:
    """从微信首页 UI 树中提取当前屏幕可见的会话联系人。

    返回的 Contact 包含联系人名称、最近消息预览、条目坐标和可点击中心点。
    """

    list_node = find_best_list(root, prefer_scrollable=False)
    if list_node is None:
        return []

    contacts: list[Contact] = []
    for item in direct_list_items(list_node):
        text_nodes = collect_text_nodes(item)
        texts = [text_node.text for text_node in text_nodes]
        if not texts or texts[0] == "搜索":
            continue

        item_bounds = node_bounds(item)
        tap_x, tap_y = bounds_center(item_bounds)
        contacts.append(
            Contact(
                name=texts[0],
                last_time=texts[1] if len(texts) > 1 else "",
                preview=" ".join(texts[2:]) if len(texts) > 2 else "",
                bounds=item_bounds,
                tap_x=tap_x,
                tap_y=tap_y,
                raw_texts=texts,
            )
        )
    return contacts


def extract_chat_title(root: dict[str, Any]) -> str:
    """从聊天页顶部区域提取当前聊天标题。

    标题用于把对方消息 sender 从通用的 `other` 替换为联系人名。
    """

    root_bounds = node_bounds(root)
    screen_width = bounds_width(root_bounds) or 1256
    screen_center_x = screen_width / 2

    candidates: list[tuple[float, str]] = []
    for node, ancestors in iter_nodes_with_ancestors(root):
        if node_type(node) != "Text":
            continue
        if any(node_type(ancestor) == "List" for ancestor in ancestors):
            continue

        text = str(attrs(node).get("text") or "").strip()
        bounds = node_bounds(node)
        if not text or bounds is None:
            continue
        x1, y1, x2, y2 = bounds
        if y1 < 100 or y2 > 360:
            continue
        if text.isdigit() or text == ":":
            continue

        center_x, _ = bounds_center(bounds)
        center_penalty = abs(center_x - screen_center_x)
        candidates.append((center_penalty + y1 / 10, text))

    if not candidates:
        return ""
    return min(candidates, key=lambda candidate: candidate[0])[1]


def extract_chat_messages(root: dict[str, Any]) -> list[ChatEntry]:
    """从聊天页 UI 树中提取当前屏幕可见的时间分隔符和消息。

    返回的 sender 仍保留底层方向判断：`self` 表示自己，`other` 表示对方。
    最终导出时会通过 `build_chat_payload` 将 `other` 替换为聊天标题。
    """

    list_node = find_best_list(root, prefer_scrollable=True)
    if list_node is None:
        return []

    root_bounds = node_bounds(root)
    screen_width = bounds_width(root_bounds) or bounds_width(node_bounds(list_node)) or 1256
    screen_center_x = screen_width / 2

    entries: list[ChatEntry] = []
    sorted_items = sorted(direct_list_items(list_node), key=lambda item: _bounds_sort_key(node_bounds(item)))
    for item in sorted_items:
        text_nodes = collect_text_nodes(item)
        texts = [text_node.text for text_node in text_nodes]

        item_bounds = node_bounds(item)
        text_bounds = text_nodes[0].bounds if text_nodes else None
        image_bounds = collect_image_bounds(item)
        if not texts:
            if not image_bounds:
                continue
            entries.append(
                ChatEntry(
                    kind="message",
                    text=infer_non_text_placeholder(image_bounds),
                    sender=_infer_sender(image_bounds, text_bounds, screen_center_x),
                    bounds=item_bounds,
                    text_bounds=text_bounds,
                    image_bounds=image_bounds,
                )
            )
            continue

        text = "\n".join(texts)

        if _looks_like_time_separator(text_nodes, image_bounds, screen_center_x):
            entries.append(
                ChatEntry(
                    kind="time",
                    text=text,
                    sender=None,
                    bounds=item_bounds,
                    text_bounds=text_bounds,
                    image_bounds=image_bounds,
                )
            )
            continue

        entries.append(
            ChatEntry(
                kind="message",
                text=text,
                sender=_infer_sender(image_bounds, text_bounds, screen_center_x),
                bounds=item_bounds,
                text_bounds=text_bounds,
                image_bounds=image_bounds,
            )
        )

    return entries


def build_chat_payload(root: dict[str, Any], *, fallback_title: str = "") -> dict[str, Any]:
    """生成单个聊天页面的导出结构。

    参数：
        root: 聊天页 UI 树。
        fallback_title: 页面标题识别失败时使用的联系人名。
    """

    title = extract_chat_title(root) or fallback_title
    return {
        "title": title,
        "messages": serialize_chat_messages(extract_chat_messages(root), other_sender=title),
    }


def build_chat_payload_from_snapshots(
    roots: list[dict[str, Any]],
    *,
    fallback_title: str = "",
    days: int | None = None,
    reference_now: datetime | None = None,
) -> dict[str, Any]:
    """从多个历史快照离线汇总聊天消息。

    参数：
        roots: 按采集顺序保存的聊天页 UI 树列表，通常从最新页到更早页。
        fallback_title: 标题识别失败时使用的联系人名。
        days: 只保留最近 N 天消息；None 表示不过滤时间范围。
        reference_now: 计算最近 N 天边界时使用的当前时间，测试时可固定。
    """

    if not roots:
        return {"title": fallback_title, "messages": []}

    title = extract_chat_title(roots[0]) or fallback_title
    cutoff = cutoff_for_days(days, reference_now or datetime.now()) if days is not None else None
    messages = merge_snapshot_messages(roots, other_sender=title, cutoff=cutoff, reference_now=reference_now)
    return {"title": title, "messages": messages}


def serialize_chat_messages(messages: list[ChatEntry], *, other_sender: str = "") -> list[dict[str, Any]]:
    """把 ChatEntry 转成 JSON 可写的字典列表。

    参数：
        messages: 底层提取出的消息列表。
        other_sender: 非空时，将 sender 为 `other` 的消息替换成该名称。
    """

    serialized = []
    for message in messages:
        item = asdict(message)
        if item["sender"] == "other" and other_sender:
            item["sender"] = other_sender
        serialized.append(item)
    return serialized


def merge_snapshot_messages(
    roots: list[dict[str, Any]],
    *,
    other_sender: str = "",
    cutoff: datetime | None = None,
    reference_now: datetime | None = None,
) -> list[dict[str, Any]]:
    """合并多个页面快照中的消息，并按指纹去重。

    参数：
        roots: 采集到的聊天页 UI 树列表。
        other_sender: 对方消息在导出结果中的 sender 名称。
        cutoff: 最近 N 天的起始时间；早于该时间的消息会被过滤。
        reference_now: 解析相对日期时使用的当前时间。
    """

    reference = reference_now or datetime.now()
    merged: list[dict[str, Any]] = []
    seen = set()
    previous_bottom_overlap_keys: set[tuple[Any, ...]] = set()
    current_time: datetime | None = None

    for root in reversed(roots):
        viewport_bounds = snapshot_viewport_bounds(root)
        current_bottom_overlap_keys: set[tuple[Any, ...]] = set()

        for entry in extract_chat_messages(root):
            entry_time = parse_chat_time(entry.text, reference) if entry.kind == "time" else None
            if entry_time is not None:
                current_time = entry_time

            if cutoff is not None:
                effective_time = entry_time if entry.kind == "time" else current_time
                if effective_time is not None and effective_time < cutoff:
                    continue

            item = asdict(entry)
            if item["sender"] == "other" and other_sender:
                item["sender"] = other_sender

            # 相邻 dump 的可视区域会重叠：上一页底部的消息可能又出现在下一页顶部。
            # 这类残留消息可能继承到不同的时间上下文，因此需要在完整指纹外再做边界去重。
            overlap_key = boundary_overlap_fingerprint(item)
            if (
                overlap_key is not None
                and is_top_boundary_message(item, viewport_bounds)
                and overlap_key in previous_bottom_overlap_keys
            ):
                continue

            key = message_fingerprint(item, current_time)
            if key in seen:
                continue
            seen.add(key)
            merged.append(item)

            if overlap_key is not None and is_bottom_boundary_message(item, viewport_bounds):
                current_bottom_overlap_keys.add(overlap_key)

        previous_bottom_overlap_keys = current_bottom_overlap_keys

    return merged


def message_fingerprint(item: dict[str, Any], current_time: datetime | None) -> tuple[Any, ...]:
    """生成消息去重指纹。

    指纹使用消息类型、发送方、文本和当前时间上下文，避免不同时间的同文消息被误合并。
    """

    timestamp = current_time.isoformat(timespec="minutes") if current_time is not None else ""
    if item.get("text") in {"[图片]", "[文件]"}:
        return item.get("kind"), item.get("sender"), item.get("text"), timestamp, tuple(item.get("image_bounds") or [])
    return item.get("kind"), item.get("sender"), item.get("text"), timestamp


def snapshot_viewport_bounds(root: dict[str, Any]) -> Bounds | None:
    """返回快照可视区域坐标，用于判断消息是否处于页面边界。

    参数：
        root: 单次 dump 得到的 UI 树根节点。
    """

    return node_bounds(root) or node_bounds(find_best_list(root, prefer_scrollable=True) or {})


def boundary_overlap_fingerprint(item: dict[str, Any]) -> tuple[Any, ...] | None:
    """生成相邻快照边界重叠去重用的内容指纹。

    参数：
        item: 已序列化的消息字典。

    仅普通文本消息使用该指纹；图片/文件占位符仍依赖完整指纹，避免误删不同媒体。
    """

    if item.get("kind") != "message":
        return None
    text = str(item.get("text") or "").strip()
    if not text or text in {"[图片]", "[文件]"}:
        return None
    normalized_text = re.sub(r"\s+", " ", text)
    return item.get("kind"), item.get("sender"), normalized_text


def is_top_boundary_message(item: dict[str, Any], viewport_bounds: Bounds | None) -> bool:
    """判断消息是否处于当前快照顶部边界区域。"""

    return is_boundary_message(item, viewport_bounds, top=True)


def is_bottom_boundary_message(item: dict[str, Any], viewport_bounds: Bounds | None) -> bool:
    """判断消息是否处于当前快照底部边界区域。"""

    return is_boundary_message(item, viewport_bounds, top=False)


def is_boundary_message(item: dict[str, Any], viewport_bounds: Bounds | None, *, top: bool) -> bool:
    """按页面高度比例判断消息是否位于顶部或底部边界区域。

    参数：
        item: 已序列化的消息字典。
        viewport_bounds: 当前快照可视区域坐标。
        top: True 时判断顶部边界，False 时判断底部边界。
    """

    item_bounds = item.get("bounds")
    if not item_bounds or viewport_bounds is None:
        return False
    _, item_y1, _, item_y2 = item_bounds
    _, view_y1, _, view_y2 = viewport_bounds
    height = max(0, view_y2 - view_y1)
    if height <= 0:
        return False
    margin = height * BOUNDARY_OVERLAP_RATIO
    if top:
        return item_y1 <= view_y1 + margin or item_y2 <= view_y1 + margin
    return item_y2 >= view_y2 - margin or item_y1 >= view_y2 - margin


def cutoff_for_days(days: int, reference_now: datetime) -> datetime:
    """计算最近 N 天采集窗口的起始时间。

    例如 reference_now 为 2026-06-11 12:00，days=7 时返回 2026-06-04 00:00。
    """

    if days < 0:
        raise ValueError("--days must be greater than or equal to 0")
    cutoff_date = reference_now.date() - timedelta(days=days)
    return datetime.combine(cutoff_date, datetime_time.min)


def parse_chat_time(text: str, reference_now: datetime | None = None) -> datetime | None:
    """解析微信聊天页中的时间文本。

    支持 `上午 10:45`、`昨天 下午 07:39`、`6/3 下午 04:43`、
    `星期一 下午 03:47`、`6月9号` 等常见形式；解析失败时返回 None。
    """

    reference = reference_now or datetime.now()
    value = text.strip()
    if not value:
        return None

    time_match = TIME_OF_DAY_RE.search(value)
    hour = minute = None
    period = ""
    if time_match:
        period = time_match.group(1) or ""
        hour = int(time_match.group(2))
        minute = int(time_match.group(3))
        hour = normalize_hour(hour, period)

    base_date = None
    if "昨天" in value:
        base_date = reference.date() - timedelta(days=1)
    elif "今天" in value:
        base_date = reference.date()

    if base_date is None:
        month_day = MONTH_DAY_RE.search(value)
        if month_day:
            year = int(month_day.group(1)) if month_day.group(1) else reference.year
            base_date = datetime(year, int(month_day.group(2)), int(month_day.group(3))).date()

    if base_date is None:
        slash_date = SLASH_DATE_RE.search(value)
        if slash_date:
            base_date = datetime(reference.year, int(slash_date.group(1)), int(slash_date.group(2))).date()

    if base_date is None:
        weekday = WEEKDAY_RE.search(value)
        if weekday:
            target_weekday = {"一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6}[
                weekday.group(1)
            ]
            delta_days = (reference.weekday() - target_weekday) % 7
            base_date = reference.date() - timedelta(days=delta_days)

    if base_date is None and time_match:
        base_date = reference.date()

    if base_date is None:
        return None

    return datetime.combine(base_date, datetime_time(hour or 0, minute or 0))


def normalize_hour(hour: int, period: str) -> int:
    """根据上午/下午/晚上等中文时段修正 24 小时制小时值。"""

    if period in {"下午", "晚上"} and hour < 12:
        return hour + 12
    if period == "中午" and hour < 11:
        return hour + 12
    if period == "凌晨" and hour == 12:
        return 0
    return hour


def _looks_like_time_separator(
    text_nodes: list[TextNode], image_bounds: list[Bounds], screen_center_x: float
) -> bool:
    """判断 ListItem 是否更像时间分隔符而不是消息气泡。"""

    if image_bounds or len(text_nodes) != 1:
        return False
    text_bounds = text_nodes[0].bounds
    if text_bounds is None:
        return True
    text_center_x, _ = bounds_center(text_bounds)
    return abs(text_center_x - screen_center_x) <= screen_center_x * 0.35


def _infer_sender(
    image_bounds: list[Bounds], text_bounds: Bounds | None, screen_center_x: float
) -> str | None:
    """根据头像或文本位置判断消息方向。"""

    avatar_bounds = _find_avatar_bounds(image_bounds)
    if avatar_bounds is not None:
        avatar_center_x, _ = bounds_center(avatar_bounds)
        return "self" if avatar_center_x > screen_center_x else "other"

    if text_bounds is None:
        return None
    text_center_x, _ = bounds_center(text_bounds)
    return "self" if text_center_x > screen_center_x else "other"


def infer_non_text_placeholder(image_bounds: list[Bounds]) -> str:
    """为没有文本的非纯文本消息生成占位符。

    当前 dump 无法可靠区分图片原图和部分无文本文件卡片；存在内容图片时默认用 `[图片]`。
    """

    avatar_bounds = _find_avatar_bounds(image_bounds)
    content_images = [bounds for bounds in image_bounds if bounds != avatar_bounds]
    return "[图片]" if content_images else "[文件]"


def _find_avatar_bounds(image_bounds: list[Bounds]) -> Bounds | None:
    """从 Image 坐标中找出最可能是头像的近似正方形图片。"""

    squareish_images = []
    for bounds in image_bounds:
        width = bounds_width(bounds)
        height = bounds_height(bounds)
        if width < 40 or height < 40:
            continue
        if abs(width - height) <= max(width, height) * 0.35:
            squareish_images.append(bounds)

    if not squareish_images:
        return None
    return min(squareish_images, key=lambda bounds: bounds_width(bounds) * bounds_height(bounds))


def dump_layout(
    output_path: str | Path,
    *,
    hdc: str = "hdc",
    remote_path: str = "/data/local/tmp/ui_tree.json",
) -> Path:
    """通过 hdc dump 当前页面并保存到本地文件。

    参数：
        output_path: 本地保存路径。
        hdc: hdc 可执行文件名或路径。
        remote_path: 设备端临时 UI 树文件路径。
    """

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)

    run_command([hdc, "shell", "uitest", "dumpLayout", "-p", remote_path])
    run_command([hdc, "file", "recv", remote_path, str(output.parent)])

    received = output.parent / Path(remote_path).name
    if received != output:
        received.replace(output)
    return output


def tap(x: int, y: int, *, hdc: str = "hdc") -> None:
    """通过 hdc 点击屏幕坐标。"""

    run_command([hdc, "shell", "uitest", "uiInput", "click", str(x), str(y)])


def swipe_history(*, hdc: str = "hdc", swipe: tuple[int, int, int, int], speed: int | None = DEFAULT_SWIPE_SPEED) -> None:
    """执行一次向历史消息方向的滑动。

    参数 swipe 为 `(x1, y1, x2, y2)`，由比例计算或命令行显式传入。
    参数 speed 为 hdc swipe 的速度值；数值越大滑动越快，为 None 时不追加速度参数。
    """

    x1, y1, x2, y2 = swipe
    command = [hdc, "shell", "uitest", "uiInput", "swipe", str(x1), str(y1), str(x2), str(y2)]
    if speed is not None:
        command.append(str(speed))
    run_command(command)


def press_back(*, hdc: str = "hdc", command: str | None = None) -> None:
    """返回上一页；可通过 command 覆盖默认 Back key 命令。"""

    if command:
        run_command(shlex.split(command))
        return
    run_command([hdc, "shell", "uitest", "uiInput", "keyEvent", "Back"])


def run_command(command: list[str]) -> None:
    """执行外部命令，失败时抛出 CalledProcessError。"""

    subprocess.run(command, check=True)


def parse_contacts_command(args: argparse.Namespace) -> None:
    """CLI 子命令：解析首页 dump 中的联系人。"""

    root = load_ui_tree(args.dump)
    print_json([asdict(contact) for contact in extract_contacts(root)], args.output)


def parse_chat_command(args: argparse.Namespace) -> None:
    """CLI 子命令：解析单个聊天页 dump 中的消息。"""

    root = load_ui_tree(args.dump)
    print_json(build_chat_payload(root), args.output)


def collect_command(args: argparse.Namespace) -> None:
    """CLI 子命令：从设备当前微信首页进入联系人并采集消息。

    参数由 argparse 注入，常用字段包括：
        target: 只采集匹配的联系人；为空时采集当前首页可见联系人。
        days: 近 N 天过滤；为空时只提取当前聊天页可见消息。
        output: 聚合 JSON 输出路径，同时会生成同名 Markdown。
        dump_dir: 原始 dump 和单会话导出文件保存目录。
    """

    dump_dir = Path(args.dump_dir)
    dump_dir.mkdir(parents=True, exist_ok=True)
    reference_now = parse_reference_now(getattr(args, "now", None))
    target = getattr(args, "target", None)
    days = getattr(args, "days", None)

    if args.start_command:
        run_command(shlex.split(args.start_command))
        time.sleep(args.wait)

    home_dump = dump_layout(dump_dir / "home.json", hdc=args.hdc, remote_path=args.remote_path)
    contacts = extract_contacts(load_ui_tree(home_dump))
    if target:
        contacts = filter_contacts(contacts, target)
        if not contacts:
            raise SystemExit(f"No contact matched target '{target}' in the current home dump.")
    if args.max_contacts is not None:
        contacts = contacts[: args.max_contacts]

    output_payload = {"home_dump": str(home_dump), "conversations": []}
    print_json_and_markdown(output_payload, args.output)

    for index, contact in enumerate(contacts, start=1):
        tap(contact.tap_x, contact.tap_y, hdc=args.hdc)
        time.sleep(args.wait)

        if days is not None:
            snapshot_paths = collect_history_snapshots(dump_dir, index, contact, args, reference_now)
            chat_payload = build_chat_payload_from_snapshots(
                [load_ui_tree(path) for path in snapshot_paths],
                fallback_title=contact.name,
                days=days,
                reference_now=reference_now,
            )
            chat_dump = snapshot_paths[0]
        else:
            chat_dump = dump_layout(
                dump_dir / f"chat_{index:02d}_{safe_filename(contact.name)}.json",
                hdc=args.hdc,
                remote_path=args.remote_path,
            )
            snapshot_paths = [chat_dump]
            chat_root = load_ui_tree(chat_dump)
            chat_payload = build_chat_payload(chat_root, fallback_title=contact.name)

        conversation = {
            "contact": asdict(contact),
            "title": chat_payload["title"],
            "dump": str(chat_dump),
            "snapshots": [str(path) for path in snapshot_paths],
            "messages": chat_payload["messages"],
        }
        output_payload["conversations"].append(conversation)
        print_json_and_markdown(conversation, chat_dump.with_suffix(".messages.json"))
        print_json_and_markdown(output_payload, args.output)

        press_back(hdc=args.hdc, command=args.back_command)
        time.sleep(args.wait)


def collect_history_snapshots(
    dump_dir: Path,
    index: int,
    contact: Contact,
    args: argparse.Namespace,
    reference_now: datetime,
) -> list[Path]:
    """进入聊天页后向历史方向滑动并保存页面快照。

    参数：
        dump_dir: 快照保存目录。
        index: 当前联系人序号，用于文件命名。
        contact: 首页提取到的联系人对象。
        args: CLI 参数，提供 hdc、days、swipe_wait、history_swipe 等设置。
        reference_now: 计算近 N 天边界和解析相对日期时使用的当前时间。
    """

    safe_name = safe_filename(contact.name)
    snapshot_paths = [
        dump_layout(
            dump_dir / f"chat_{index:02d}_{safe_name}.json",
            hdc=args.hdc,
            remote_path=args.remote_path,
        )
    ]
    max_history_swipes = getattr(args, "max_history_swipes", 80)
    stable_swipes = getattr(args, "stable_swipes", 3)
    swipe_wait = getattr(args, "swipe_wait", None)
    swipe_speed = normalize_swipe_speed(getattr(args, "swipe_speed", DEFAULT_SWIPE_SPEED))
    explicit_history_swipe = parse_swipe(getattr(args, "history_swipe", None))
    history_swipe_ratio = getattr(args, "history_swipe_ratio", DEFAULT_HISTORY_SWIPE_RATIO)
    cutoff = cutoff_for_days(getattr(args, "days"), reference_now)

    stable_count = 0
    root = load_ui_tree(snapshot_paths[-1])
    last_fingerprint = page_fingerprint(root)
    if snapshot_reaches_cutoff(root, cutoff, reference_now):
        return snapshot_paths

    for swipe_index in range(1, max_history_swipes + 1):
        history_swipe = explicit_history_swipe or compute_history_swipe(root, history_swipe_ratio)
        swipe_history(hdc=args.hdc, swipe=history_swipe, speed=swipe_speed)
        if swipe_wait is not None:
            time.sleep(swipe_wait)
        next_path = dump_layout(
            dump_dir / f"chat_{index:02d}_{safe_name}_history_{swipe_index:03d}.json",
            hdc=args.hdc,
            remote_path=args.remote_path,
        )
        snapshot_paths.append(next_path)

        root = load_ui_tree(next_path)
        fingerprint = page_fingerprint(root)
        stable_count = stable_count + 1 if fingerprint == last_fingerprint else 0
        last_fingerprint = fingerprint

        if snapshot_reaches_cutoff(root, cutoff, reference_now) or stable_count >= stable_swipes:
            break

    return snapshot_paths


def compute_history_swipe(root: dict[str, Any], ratio: float = DEFAULT_HISTORY_SWIPE_RATIO) -> tuple[int, int, int, int]:
    """按页面尺寸比例计算历史滑动坐标。

    参数：
        root: 最近一次聊天页 UI 树，用其根节点 bounds 获取屏幕尺寸。
        ratio: 滑动距离占页面高度的比例；默认 0.65。
    """

    if ratio <= 0:
        raise ValueError("--history-swipe-ratio must be greater than 0")
    bounds = node_bounds(root) or (0, 0, 1256, 2760)
    x1, y1, x2, y2 = bounds
    center_x = (x1 + x2) / 2
    center_y = (y1 + y2) / 2
    half_distance = bounds_height(bounds) * ratio / 2
    start_y = max(y1, round(center_y - half_distance))
    end_y = min(y2, round(center_y + half_distance))
    center_x = round(center_x)
    return center_x, start_y, center_x, end_y


def snapshot_reaches_cutoff(root: dict[str, Any], cutoff: datetime, reference_now: datetime) -> bool:
    """判断快照内最早可解析时间是否已经早于采集起点。"""

    times = [
        parsed_time
        for entry in extract_chat_messages(root)
        if entry.kind == "time"
        for parsed_time in [parse_chat_time(entry.text, reference_now)]
        if parsed_time is not None
    ]
    return bool(times and min(times) < cutoff)


def page_fingerprint(root: dict[str, Any]) -> tuple[tuple[Any, ...], ...]:
    """生成页面内容指纹，用于判断连续滑动后页面是否不再变化。"""

    return tuple(
        (entry.kind, entry.sender, entry.text, entry.bounds, entry.text_bounds)
        for entry in extract_chat_messages(root)
    )


def filter_contacts(contacts: list[Contact], target: str) -> list[Contact]:
    """按 target 过滤联系人，优先精确匹配，再回退到包含匹配。"""

    exact = [contact for contact in contacts if contact.name == target]
    if exact:
        return exact
    return [contact for contact in contacts if target in contact.name]


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


def normalize_swipe_speed(value: int | None) -> int | None:
    """规范化 `--swipe-speed` 参数。

    数值越大，单次滑动越快；0 表示不向 hdc swipe 命令追加速度参数。
    """

    if value is None or value == 0:
        return None
    if value < 0:
        raise ValueError("--swipe-speed must be greater than or equal to 0")
    return value


def safe_filename(value: str) -> str:
    """把联系人名转换成适合用作文件名的字符串。"""

    cleaned = re.sub(r"[^\w.-]+", "_", value, flags=re.UNICODE).strip("_")
    return cleaned or "chat"


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
        help="Speed argument appended to hdc uiInput swipe; larger values swipe faster. Use 0 to omit it. Default: 2500.",
    )
    collect_parser.add_argument(
        "--history-swipe",
        help="History swipe coordinates as x1,y1,x2,y2. Overrides ratio-based swipe calculation.",
    )
    collect_parser.add_argument(
        "--history-swipe-ratio",
        type=float,
        default=DEFAULT_HISTORY_SWIPE_RATIO,
        help="Total history swipe distance as a ratio of page height. Default: 0.65.",
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
