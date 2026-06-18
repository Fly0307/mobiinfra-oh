"""微信 UI dump 的设备采集流程。"""

from __future__ import annotations

import shlex
import subprocess
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from .parser import (
    Contact,
    DEFAULT_HISTORY_SWIPE_RATIO,
    DEFAULT_SWIPE_SPEED,
    build_chat_payload,
    build_chat_payload_from_snapshots,
    compute_history_swipe,
    cutoff_for_days,
    extract_chat_messages,
    extract_contacts,
    filter_contacts,
    load_ui_tree,
    parse_chat_time,
    safe_filename,
)

CollectionUpdate = Callable[[dict[str, Any], dict[str, Any] | None, Path | None], None]


@dataclass(frozen=True)
class HistorySnapshotOptions:
    """历史消息快照采集参数，供 CLI 和后续服务复用。"""

    days: int
    hdc: str = "hdc"
    remote_path: str = "/data/local/tmp/ui_tree.json"
    max_history_swipes: int = 80
    stable_swipes: int = 3
    swipe_wait: float | None = None
    swipe_speed: int | None = DEFAULT_SWIPE_SPEED
    history_swipe: tuple[int, int, int, int] | None = None
    history_swipe_ratio: float = DEFAULT_HISTORY_SWIPE_RATIO

    def __post_init__(self) -> None:
        validate_history_snapshot_options(self)


@dataclass(frozen=True)
class CollectOptions:
    """从微信首页进入会话并采集消息的参数集合。"""

    dump_dir: str | Path = "dumps"
    hdc: str = "hdc"
    remote_path: str = "/data/local/tmp/ui_tree.json"
    wait: float = 1.0
    max_contacts: int | None = None
    target: str | None = None
    days: int | None = None
    max_history_swipes: int = 80
    stable_swipes: int = 3
    swipe_wait: float | None = None
    swipe_speed: int | None = DEFAULT_SWIPE_SPEED
    history_swipe: tuple[int, int, int, int] | None = None
    history_swipe_ratio: float = DEFAULT_HISTORY_SWIPE_RATIO
    reference_now: datetime | None = None
    start_command: str | None = None
    back_command: str | None = None

    def __post_init__(self) -> None:
        validate_collect_options(self)


def validate_collect_options(options: CollectOptions) -> None:
    """在触碰设备前校验采集参数，避免错误配置造成误点击。"""

    _validate_optional_non_negative_int(options.max_contacts, "max_contacts")
    _validate_optional_non_negative_int(options.days, "days")
    _validate_non_negative_float(options.wait, "wait")
    _validate_history_collection_values(
        max_history_swipes=options.max_history_swipes,
        stable_swipes=options.stable_swipes,
        swipe_wait=options.swipe_wait,
        swipe_speed=options.swipe_speed,
        history_swipe=options.history_swipe,
        history_swipe_ratio=options.history_swipe_ratio,
    )


def validate_history_snapshot_options(options: HistorySnapshotOptions) -> None:
    """校验历史快照采集参数，供 CLI 和服务层共用。"""

    _validate_non_negative_int(options.days, "days")
    _validate_history_collection_values(
        max_history_swipes=options.max_history_swipes,
        stable_swipes=options.stable_swipes,
        swipe_wait=options.swipe_wait,
        swipe_speed=options.swipe_speed,
        history_swipe=options.history_swipe,
        history_swipe_ratio=options.history_swipe_ratio,
    )


def _validate_history_collection_values(
    *,
    max_history_swipes: int,
    stable_swipes: int,
    swipe_wait: float | None,
    swipe_speed: int | None,
    history_swipe: tuple[int, int, int, int] | None,
    history_swipe_ratio: float,
) -> None:
    _validate_non_negative_int(max_history_swipes, "max_history_swipes")
    _validate_non_negative_int(stable_swipes, "stable_swipes")
    _validate_optional_non_negative_float(swipe_wait, "swipe_wait")
    normalize_swipe_speed(swipe_speed)
    _validate_history_swipe(history_swipe)
    if history_swipe_ratio <= 0:
        raise ValueError("history_swipe_ratio must be greater than 0")


def _validate_non_negative_int(value: int, name: str) -> None:
    if value < 0:
        raise ValueError(f"{name} must be greater than or equal to 0")


def _validate_optional_non_negative_int(value: int | None, name: str) -> None:
    if value is not None:
        _validate_non_negative_int(value, name)


def _validate_non_negative_float(value: float, name: str) -> None:
    if value < 0:
        raise ValueError(f"{name} must be greater than or equal to 0")


def _validate_optional_non_negative_float(value: float | None, name: str) -> None:
    if value is not None:
        _validate_non_negative_float(value, name)


def _validate_history_swipe(value: tuple[int, int, int, int] | None) -> None:
    if value is None:
        return
    if len(value) != 4:
        raise ValueError("history_swipe must contain exactly four coordinates")
    if not all(isinstance(part, int) for part in value):
        raise ValueError("history_swipe coordinates must be integers")


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


def collect_visible_chats(options: CollectOptions, on_update: CollectionUpdate | None = None) -> dict[str, Any]:
    """采集当前微信首页可见会话并返回聚合 payload。

    参数：
        options: 显式采集参数，避免服务端复用时依赖 CLI 参数对象。
        on_update: 可选进度回调，CLI 用它保持原有的增量 JSON/Markdown 写入行为。
    """

    dump_dir = Path(options.dump_dir)
    dump_dir.mkdir(parents=True, exist_ok=True)
    reference_now = options.reference_now or datetime.now()

    if options.start_command:
        run_command(shlex.split(options.start_command))
        time.sleep(options.wait)

    home_dump = dump_layout(dump_dir / "home.json", hdc=options.hdc, remote_path=options.remote_path)
    contacts = extract_contacts(load_ui_tree(home_dump))
    if options.target:
        contacts = filter_contacts(contacts, options.target)
        if not contacts:
            raise ValueError(f"No contact matched target '{options.target}' in the current home dump.")
    if options.max_contacts is not None:
        contacts = contacts[: options.max_contacts]
    validate_contacts_are_tappable(contacts)

    output_payload: dict[str, Any] = {"home_dump": str(home_dump), "conversations": []}
    if on_update is not None:
        on_update(output_payload, None, None)

    for index, contact in enumerate(contacts, start=1):
        tap(contact.tap_x, contact.tap_y, hdc=options.hdc)
        collection_error: BaseException | None = None
        try:
            time.sleep(options.wait)

            if options.days is not None:
                history_options = HistorySnapshotOptions(
                    days=options.days,
                    hdc=options.hdc,
                    remote_path=options.remote_path,
                    max_history_swipes=options.max_history_swipes,
                    stable_swipes=options.stable_swipes,
                    swipe_wait=options.swipe_wait,
                    swipe_speed=options.swipe_speed,
                    history_swipe=options.history_swipe,
                    history_swipe_ratio=options.history_swipe_ratio,
                )
                snapshot_paths = collect_history_snapshots(dump_dir, index, contact, history_options, reference_now)
                chat_payload = build_chat_payload_from_snapshots(
                    [load_ui_tree(path) for path in snapshot_paths],
                    fallback_title=contact.name,
                    days=options.days,
                    reference_now=reference_now,
                )
                chat_dump = snapshot_paths[0]
            else:
                chat_dump = dump_layout(
                    dump_dir / f"chat_{index:02d}_{safe_filename(contact.name)}.json",
                    hdc=options.hdc,
                    remote_path=options.remote_path,
                )
                snapshot_paths = [chat_dump]
                chat_payload = build_chat_payload(load_ui_tree(chat_dump), fallback_title=contact.name)

            conversation = {
                "contact": asdict(contact),
                "title": chat_payload["title"],
                "dump": str(chat_dump),
                "snapshots": [str(path) for path in snapshot_paths],
                "messages": chat_payload["messages"],
            }
            output_payload["conversations"].append(conversation)
            if on_update is not None:
                on_update(output_payload, conversation, chat_dump)
        except BaseException as exc:
            collection_error = exc
            raise
        finally:
            press_back_after_chat(options, original_error=collection_error)
            time.sleep(options.wait)

    return output_payload


def validate_contacts_are_tappable(contacts: list[Contact]) -> None:
    """确认联系人条目有可点击坐标，避免 malformed dump 触发 `(0, 0)` 点击。"""

    for contact in contacts:
        if contact.bounds is None:
            raise ValueError(f"Contact '{contact.name}' has no bounds and cannot be tapped safely")


def press_back_after_chat(options: CollectOptions, *, original_error: BaseException | None) -> None:
    """离开聊天页；失败时优先保留原始采集异常。"""

    try:
        press_back(hdc=options.hdc, command=options.back_command)
    except BaseException as back_error:
        if original_error is not None:
            back_error.__context__ = None
            original_error.__context__ = back_error
            return
        raise


def collect_history_snapshots(
    dump_dir: Path,
    index: int,
    contact: Contact,
    options: HistorySnapshotOptions,
    reference_now: datetime,
) -> list[Path]:
    """进入聊天页后向历史方向滑动并保存页面快照。"""

    safe_name = safe_filename(contact.name)
    snapshot_paths = [
        dump_layout(
            dump_dir / f"chat_{index:02d}_{safe_name}.json",
            hdc=options.hdc,
            remote_path=options.remote_path,
        )
    ]
    swipe_speed = normalize_swipe_speed(options.swipe_speed)
    cutoff = cutoff_for_days(options.days, reference_now)

    stable_count = 0
    root = load_ui_tree(snapshot_paths[-1])
    last_fingerprint = page_fingerprint(root)
    if snapshot_reaches_cutoff(root, cutoff, reference_now):
        return snapshot_paths

    for swipe_index in range(1, options.max_history_swipes + 1):
        history_swipe = options.history_swipe or compute_history_swipe(root, options.history_swipe_ratio)
        swipe_history(hdc=options.hdc, swipe=history_swipe, speed=swipe_speed)
        if options.swipe_wait is not None:
            time.sleep(options.swipe_wait)
        next_path = dump_layout(
            dump_dir / f"chat_{index:02d}_{safe_name}_history_{swipe_index:03d}.json",
            hdc=options.hdc,
            remote_path=options.remote_path,
        )
        snapshot_paths.append(next_path)

        root = load_ui_tree(next_path)
        fingerprint = page_fingerprint(root)
        stable_count = stable_count + 1 if fingerprint == last_fingerprint else 0
        last_fingerprint = fingerprint

        if snapshot_reaches_cutoff(root, cutoff, reference_now) or stable_count >= options.stable_swipes:
            break

    return snapshot_paths


def snapshot_reaches_cutoff(root: dict[str, Any], cutoff: datetime, reference_now: datetime) -> bool:
    """判断快照内是否已经出现早于采集起始日期的时间分隔符。

    微信近几天的时间分隔符常显示为“昨天”或“星期X”。采集时需要滑过完整
    目标日期范围，所以只有出现比 cutoff 更早的日期时才停止。
    """

    times = [
        parsed_time
        for entry in extract_chat_messages(root)
        if entry.kind == "time"
        for parsed_time in [parse_chat_time(entry.text, reference_now)]
        if parsed_time is not None
    ]
    if not times:
        return False
    earliest_time = min(times)
    return earliest_time < cutoff


def page_fingerprint(root: dict[str, Any]) -> tuple[tuple[Any, ...], ...]:
    """生成页面内容指纹，用于判断连续滑动后页面是否不再变化。"""

    return tuple(
        (entry.kind, entry.sender, entry.text, entry.bounds, entry.text_bounds)
        for entry in extract_chat_messages(root)
    )


def normalize_swipe_speed(value: int | None) -> int | None:
    """规范化 `--swipe-speed` 参数。

    数值越大，单次滑动越快；0 表示不向 hdc swipe 命令追加速度参数。
    """

    if value is None or value == 0:
        return None
    if value < 0:
        raise ValueError("--swipe-speed must be greater than or equal to 0")
    return value
