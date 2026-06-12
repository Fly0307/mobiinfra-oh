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
import time
from dataclasses import asdict, dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from .config import (
    DEFAULT_DAYS,
    DEFAULT_HDC_TIMEOUT,
    DEFAULT_HISTORY_SWIPE_RATIO,
    DEFAULT_MAX_CONTACTS,
    DEFAULT_MAX_HISTORY_SWIPES,
    DEFAULT_MAX_LIST_SWIPES,
    DEFAULT_STABLE_SWIPES,
    DEFAULT_SWIPE_SPEED,
    DEFAULT_WAIT,
    SUPPORTED_MODES,
    WECHAT_ABILITY_CANDIDATES,
    WECHAT_BUNDLES,
)
from .parser import (
    Contact,
    attrs,
    build_chat_payload_from_snapshots,
    build_chat_payload,
    bounds_center,
    compute_history_swipe,
    cutoff_for_days,
    collect_text_nodes,
    direct_list_items,
    extract_contacts,
    extract_chat_messages,
    find_best_list,
    iter_nodes,
    load_ui_tree,
    node_bounds,
    node_type,
    parse_chat_time,
    safe_filename,
)
from .render import markdown_path_for_json, print_json_and_markdown


DriverCall = Callable[[str, Callable[[Any], Any]], Any]


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
                f"## 微信联系人「{contact_name}」当前可见页面消息采集",
                "",
                f"- 采集范围：请求最近 {days} 天，未展开历史",
                f"- 联系人：{contact_name}",
                f"- 会话标题：{title}",
            ]
        else:
            lines = [
                f"## 微信联系人「{contact_name}」最近 {days} 天消息采集",
                "",
                f"- 联系人：{contact_name}",
                f"- 会话标题：{title}",
            ]
        time_range = _format_time_range(conversation.get("time_range"))
        if time_range:
            lines.append(f"- 时间范围：{time_range}")
        lines.extend([f"- 消息数：{message_count}", "", "### 完整消息摘录", ""])

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
    driver_call: DriverCall | None = None,
) -> dict[str, Any]:
    """通过 HDC 适配器执行微信采集服务编排。"""

    prefix = _split_hdc_prefix(hdc_prefix)
    remote_path = "/data/local/tmp/ui_tree.json"
    request = normalize_collect_request(payload)

    # 最近联系人模式优先通过 hmdriver2 操作设备，并保留 HDC/UI dump 兜底能力。
    _open_wechat_app(prefix, request.wait, driver_call=driver_call)

    def dump_provider(path: Path) -> dict[str, Any]:
        path.parent.mkdir(parents=True, exist_ok=True)
        print(f">> [WeChatCollect] 执行 UI dump: {path}")
        if not _run_driver_preferred(
            driver_call,
            "Driver.shell(dumpLayout)",
            lambda driver: driver.shell(f"uitest dumpLayout -p {remote_path}"),
        ):
            _run_hdc(prefix + ["shell", "uitest", "dumpLayout", "-p", remote_path])
        _run_hdc(prefix + ["file", "recv", remote_path, str(path.parent)])

        received_path = path.parent / Path(remote_path).name
        if received_path.exists() and received_path != path:
            received_path.replace(path)
        if not path.exists():
            raise RuntimeError(f"ui dump file not found: {path}")
        print(f">> [WeChatCollect] UI dump 已保存: {path}")
        return load_ui_tree(path)

    def tap_contact(contact: Contact) -> None:
        print(f">> [WeChatCollect] 点击联系人: {contact.name} ({contact.tap_x},{contact.tap_y})")
        if not _run_driver_preferred(
            driver_call,
            "Driver.click",
            lambda driver: driver.click(contact.tap_x, contact.tap_y),
        ):
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "click", str(contact.tap_x), str(contact.tap_y)])

    def click_point(x: int, y: int, label: str) -> None:
        print(f">> [WeChatCollect] 点击{label}: ({x},{y})")
        if not _run_driver_preferred(
            driver_call,
            f"Driver.click({label})",
            lambda driver: driver.click(x, y),
        ):
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "click", str(x), str(y)])

    def input_text(text: str) -> None:
        print(f">> [WeChatCollect] 输入搜索关键词: {text}")
        if not _run_driver_preferred(
            driver_call,
            "Driver.input_text(search)",
            lambda driver: _driver_clear_and_input_text(driver, text),
        ):
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "keyEvent", "2072", "2017"])
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "keyEvent", "2071"])
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "inputText", text])

    def press_back() -> None:
        print(">> [WeChatCollect] 返回微信会话列表")
        if not _run_driver_preferred(
            driver_call,
            "Driver.press_key(BACK)",
            lambda driver: driver.press_key(2),
        ):
            _run_hdc(prefix + ["shell", "uitest", "uiInput", "keyEvent", "Back"])

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
        print(f">> [WeChatCollect] 滑动微信会话列表: speed={request.swipe_speed}")
        if not _run_driver_preferred(
            driver_call,
            "Driver.swipe(contact_list)",
            lambda driver: driver.swipe(628, 2200, 628, 700, speed=max(1, request.swipe_speed)),
        ):
            _run_hdc(command)

    def swipe_chat_history(root: dict[str, Any], request: WechatCollectRequest) -> None:
        x1, y1, x2, y2 = compute_history_swipe(root, request.history_swipe_ratio)
        command = [*prefix, "shell", "uitest", "uiInput", "swipe", str(x1), str(y1), str(x2), str(y2)]
        if request.swipe_speed > 0:
            command.append(str(request.swipe_speed))
        print(
            f">> [WeChatCollect] 滑动聊天历史: ({x1},{y1})->({x2},{y2}), "
            f"speed={request.swipe_speed}"
        )
        if not _run_driver_preferred(
            driver_call,
            "Driver.swipe(chat_history)",
            lambda driver: driver.swipe(x1, y1, x2, y2, speed=max(1, request.swipe_speed)),
        ):
            _run_hdc(command)

    def search_target_contact(contact_name: str, search_request: WechatCollectRequest, output_dir: Path) -> Any:
        result = _search_target_contact_with_ui_dump(
            contact_name,
            search_request,
            output_dir,
            dump_provider,
            click_point,
            input_text,
        )
        if _gui_search_succeeded(result):
            return result
        fallback_result = gui_search(contact_name)
        if _gui_search_succeeded(fallback_result):
            return fallback_result
        return result

    return collect_action_with_device(
        asdict(request),
        dump_provider=dump_provider,
        tap_contact=tap_contact,
        press_back=press_back,
        swipe_history=swipe_chat_history,
        gui_search=gui_search,
        swipe_contacts=swipe_contacts,
        collect_history=True,
        target_search=search_target_contact,
    )


def collect_action_with_device(
    payload: dict[str, Any],
    dump_provider: Callable[[Path], dict[str, Any]],
    tap_contact: Callable[[Contact], None],
    press_back: Callable[[], None],
    swipe_history: Callable[[dict[str, Any], WechatCollectRequest], Any],
    gui_search: Callable[[str], Any],
    swipe_contacts: Callable[[dict[str, Any], WechatCollectRequest], Any] | None = None,
    collect_history: bool = False,
    target_search: Callable[[str, WechatCollectRequest, Path], Any] | None = None,
) -> dict[str, Any]:
    """使用注入的设备操作执行可测试的微信采集编排。

    该入口只负责编排首页 dump、联系人点击、聊天页 dump、导出文件和 daily-log
    生成。真实设备操作由调用方注入，单元测试可替换为假设备实现。
    """

    request = normalize_collect_request(payload)
    started_at = datetime.now().replace(microsecond=0)
    default_run_id = f"wechat-{started_at.strftime('%Y%m%dT%H%M%S')}"
    output_dir = _resolve_output_dir(request.output_dir, default_run_id + "-")
    run_id = output_dir.name if request.output_dir else default_run_id
    print(
        f">> [WeChatCollect] 开始采集: mode={request.mode}, days={request.days}, "
        f"max_contacts={request.max_contacts}, output_dir={output_dir}"
    )

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
        print(f">> [WeChatCollect] 最近联系人候选数: {len(contacts)}")
        if contacts:
            print(">> [WeChatCollect] 最近联系人: " + ", ".join(contact.name for contact in contacts))
        else:
            raise RuntimeError(f"未识别到微信最近联系人，请确认微信已进入聊天首页；dump 输出目录：{output_dir}")

        for index, contact in enumerate(contacts, start=1):
            tap_contact(contact)
            collection_error: BaseException | None = None
            try:
                chat_path = output_dir / f"chat_{index:02d}_{safe_filename(contact.name)}.json"
                chat_root = dump_provider(chat_path)
                if collect_history:
                    conversations.append(_conversation_from_history_snapshots(
                        contact,
                        *_collect_history_snapshots(
                            output_dir,
                            index,
                            contact,
                            chat_root,
                            chat_path,
                            request,
                            dump_provider,
                            swipe_history,
                        ),
                        days=request.days,
                    ))
                else:
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
        if target_search is not None:
            search_result = target_search(request.target_contact, request, output_dir)
        else:
            search_result = gui_search(request.target_contact)
        if not _gui_search_succeeded(search_result):
            raise RuntimeError("指定联系人搜索失败")

        contact = _contact_from_search_result(search_result, request.target_contact)
        chat_path = output_dir / f"chat_01_{safe_filename(request.target_contact)}.json"
        collection_error: BaseException | None = None
        try:
            chat_root = dump_provider(chat_path)
            if collect_history:
                conversations.append(_conversation_from_history_snapshots(
                    contact,
                    *_collect_history_snapshots(
                        output_dir,
                        1,
                        contact,
                        chat_root,
                        chat_path,
                        request,
                        dump_provider,
                        swipe_history,
                    ),
                    days=request.days,
                ))
            else:
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


def _search_target_contact_with_ui_dump(
    contact_name: str,
    request: WechatCollectRequest,
    output_dir: Path,
    dump_provider: Callable[[Path], dict[str, Any]],
    click_point: Callable[[int, int, str], None],
    input_text: Callable[[str], None],
) -> dict[str, Any]:
    """使用微信自身搜索框进入指定联系人聊天页。

    该路径不依赖视觉 GUI Agent：先从当前微信页面 dump 中定位“搜索”入口，
    再输入联系人名并从搜索结果 dump 中选择匹配联系人。
    """

    print(f">> [WeChatCollect] 通过 UI dump 搜索指定联系人: {contact_name}")
    search_home_path = output_dir / "target_search_home.json"
    search_home = dump_provider(search_home_path)
    search_point = _find_search_entry_point(search_home)
    if search_point is None:
        return {
            "status": "error",
            "message": "未找到微信搜索入口",
            "search_home_dump": str(search_home_path),
        }

    click_point(search_point[0], search_point[1], "微信搜索入口")
    if request.wait > 0:
        time.sleep(request.wait)
    input_text(contact_name)
    if request.wait > 0:
        time.sleep(request.wait)

    search_results_path = output_dir / "target_search_results.json"
    search_results = dump_provider(search_results_path)
    contact = _find_target_contact_in_search_results(search_results, contact_name)
    if contact is None:
        return {
            "status": "error",
            "message": f"未在微信搜索结果中找到联系人：{contact_name}",
            "search_home_dump": str(search_home_path),
            "search_results_dump": str(search_results_path),
        }

    click_point(contact.tap_x, contact.tap_y, f"搜索结果联系人 {contact.name}")
    if request.wait > 0:
        time.sleep(request.wait)
    return {
        "status": "ok",
        "contact": _serialize_contact(contact),
        "search_home_dump": str(search_home_path),
        "search_results_dump": str(search_results_path),
    }


def _driver_clear_and_input_text(driver: Any, text: str) -> None:
    driver.shell("uitest uiInput keyEvent 2072 2017")
    driver.press_key(2071)
    driver.input_text(text)


def _find_search_entry_point(root: dict[str, Any]) -> tuple[int, int] | None:
    candidates: list[tuple[int, tuple[int, int]]] = []
    for node in iter_nodes(root):
        if node_type(node) != "Text":
            continue
        text = str(attrs(node).get("text") or "").strip()
        if text != "搜索":
            continue
        bounds = node_bounds(node)
        if bounds is None:
            continue
        candidates.append((bounds[1], bounds_center(bounds)))
    if candidates:
        return min(candidates, key=lambda item: item[0])[1]

    root_bounds = node_bounds(root)
    if root_bounds is None:
        return None
    x1, y1, x2, y2 = root_bounds
    return (x1 + x2) // 2, y1 + max(160, int((y2 - y1) * 0.065))


def _find_target_contact_in_search_results(root: dict[str, Any], target_name: str) -> Contact | None:
    list_node = find_best_list(root, prefer_scrollable=False)
    candidates: list[tuple[int, int, Contact]] = []
    if list_node is not None:
        for item in direct_list_items(list_node):
            text_nodes = collect_text_nodes(item)
            texts = [text_node.text for text_node in text_nodes]
            score, matched_name = _target_contact_match(texts, target_name)
            if score <= 0:
                continue
            item_bounds = node_bounds(item)
            tap_x, tap_y = bounds_center(item_bounds)
            contact_name = matched_name or target_name
            candidates.append((
                score,
                -(item_bounds[1] if item_bounds is not None else 0),
                Contact(
                    name=contact_name,
                    last_time="",
                    preview=" ".join(texts[1:]) if len(texts) > 1 else "",
                    bounds=item_bounds,
                    tap_x=tap_x,
                    tap_y=tap_y,
                    raw_texts=texts or [target_name],
                ),
            ))
    if candidates:
        return max(candidates, key=lambda item: (item[0], item[1]))[2]

    for node in iter_nodes(root):
        if node_type(node) != "Text":
            continue
        text = str(attrs(node).get("text") or "").strip()
        score, matched_name = _target_contact_match([text], target_name)
        if score <= 0:
            continue
        bounds = node_bounds(node)
        tap_x, tap_y = bounds_center(bounds)
        return Contact(
            name=matched_name or target_name,
            last_time="",
            preview="",
            bounds=bounds,
            tap_x=tap_x,
            tap_y=tap_y,
            raw_texts=[text or target_name],
        )
    return None


def _target_contact_match_score(texts: list[str], target_name: str) -> int:
    score, _ = _target_contact_match(texts, target_name)
    return score


def _target_contact_match(texts: list[str], target_name: str) -> tuple[int, str]:
    target = target_name.strip()
    if not target:
        return 0, ""
    normalized_target = target.casefold()
    normalized_pairs = [
        (text.strip(), text.strip().casefold())
        for text in texts
        if text and text.strip()
    ]
    if not normalized_pairs:
        return 0, ""
    first_text, first = normalized_pairs[0]
    if first == normalized_target:
        return 100, first_text
    if normalized_target in first or first in normalized_target:
        return 80, first_text
    for text, normalized_text in normalized_pairs:
        if normalized_text == normalized_target:
            return 70, text
        if normalized_target in normalized_text or normalized_text in normalized_target:
            return 50, text
    return 0, ""


def _contact_from_search_result(result: Any, fallback_name: str) -> Contact:
    if isinstance(result, dict) and isinstance(result.get("contact"), dict):
        item = result["contact"]
        name = str(item.get("name") or fallback_name).strip() or fallback_name
        bounds = _bounds_from_json_value(item.get("bounds"))
        tap_x = _int_or_default(item.get("tap_x"), bounds_center(bounds)[0])
        tap_y = _int_or_default(item.get("tap_y"), bounds_center(bounds)[1])
        raw_texts = item.get("raw_texts")
        return Contact(
            name=name,
            last_time=str(item.get("last_time") or ""),
            preview=str(item.get("preview") or ""),
            bounds=bounds,
            tap_x=tap_x,
            tap_y=tap_y,
            raw_texts=[str(value) for value in raw_texts] if isinstance(raw_texts, list) else [name],
        )
    return Contact(
        name=fallback_name,
        last_time="",
        preview="",
        bounds=None,
        tap_x=0,
        tap_y=0,
        raw_texts=[fallback_name],
    )


def _bounds_from_json_value(value: Any) -> tuple[int, int, int, int] | None:
    if not isinstance(value, (list, tuple)) or len(value) != 4:
        return None
    try:
        return tuple(int(part) for part in value)  # type: ignore[return-value]
    except (TypeError, ValueError):
        return None


def _int_or_default(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


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


def _collect_history_snapshots(
    output_dir: Path,
    index: int,
    contact: Contact,
    initial_root: dict[str, Any],
    initial_path: Path,
    request: WechatCollectRequest,
    dump_provider: Callable[[Path], dict[str, Any]],
    swipe_history: Callable[[dict[str, Any], WechatCollectRequest], Any],
) -> tuple[list[dict[str, Any]], list[str]]:
    """在聊天页内向历史方向滑动，保存并返回多页 dump。

    初始页总是保留；后续页面按 `max_history_swipes` 控制。到达请求时间范围
    或连续稳定页数达到阈值后停止，避免无意义长时间滑动。
    """

    roots = [initial_root]
    paths = [str(initial_path)]
    if request.max_history_swipes <= 0:
        return roots, paths

    reference_now = datetime.now()
    cutoff = cutoff_for_days(request.days, reference_now)
    stable_count = 0
    current_root = initial_root
    last_fingerprint = _page_fingerprint(current_root)
    if _snapshot_reaches_cutoff(current_root, cutoff, reference_now):
        return roots, paths

    safe_name = safe_filename(contact.name)
    for swipe_index in range(1, request.max_history_swipes + 1):
        swipe_result = swipe_history(current_root, request)
        if request.wait > 0:
            time.sleep(request.wait)
        if isinstance(swipe_result, dict):
            current_root = swipe_result
        next_path = output_dir / f"chat_{index:02d}_{safe_name}_history_{swipe_index:03d}.json"
        current_root = dump_provider(next_path)
        roots.append(current_root)
        paths.append(str(next_path))

        fingerprint = _page_fingerprint(current_root)
        stable_count = stable_count + 1 if fingerprint == last_fingerprint else 0
        last_fingerprint = fingerprint
        print(
            f">> [WeChatCollect] 历史快照 {swipe_index}: stable={stable_count}/"
            f"{request.stable_swipes}, snapshots={len(paths)}"
        )
        if _snapshot_reaches_cutoff(current_root, cutoff, reference_now) or stable_count >= request.stable_swipes:
            break
    return roots, paths


def _conversation_from_history_snapshots(
    contact: Contact,
    roots: list[dict[str, Any]],
    paths: list[str],
    days: int,
) -> dict[str, Any]:
    """把多页历史 dump 合并成统一会话记录。"""

    chat_payload = build_chat_payload_from_snapshots(roots, fallback_title=contact.name, days=days)
    messages = chat_payload["messages"]
    time_range = _messages_time_range(messages)
    history_mode = "history_scrolled" if len(paths) > 1 else "visible_page_only"
    time_range["mode"] = history_mode
    return {
        "contact": _serialize_contact(contact),
        "title": chat_payload["title"],
        "dump": paths[0] if paths else "",
        "snapshots": paths,
        "messages": messages,
        "history_mode": history_mode,
        "time_range": time_range,
    }


def _snapshot_reaches_cutoff(root: dict[str, Any], cutoff: datetime, reference_now: datetime) -> bool:
    parsed_times = [
        parsed
        for entry in extract_chat_messages(root)
        if entry.kind == "time"
        for parsed in [parse_chat_time(entry.text, reference_now)]
        if parsed is not None
    ]
    return bool(parsed_times and min(parsed_times) < cutoff)


def _page_fingerprint(root: dict[str, Any]) -> tuple[tuple[Any, ...], ...]:
    return tuple(
        (entry.kind, entry.sender, entry.text, entry.bounds, entry.text_bounds)
        for entry in extract_chat_messages(root)
    )


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


def _open_wechat_app(prefix: list[str], wait: float, driver_call: DriverCall | None = None) -> None:
    """采集前将微信拉到前台；优先 hmdriver2，失败时用 HDC 显式 Ability 兜底。"""

    if _open_wechat_app_with_driver(driver_call, wait):
        return

    last_error: Exception | None = None
    for bundle in WECHAT_BUNDLES:
        for ability in _wechat_ability_candidates(prefix, bundle):
            try:
                print(f">> [WeChatCollect] 尝试启动微信: bundle={bundle}, ability={ability}")
                _run_hdc(prefix + ["shell", "aa", "start", "-a", ability, "-b", bundle])
                if wait > 0:
                    time.sleep(wait)
                print(f">> [WeChatCollect] 微信启动命令完成: bundle={bundle}, ability={ability}")
                return
            except Exception as ex:
                last_error = ex
    if last_error is not None:
        raise RuntimeError(f"failed to launch WeChat: {last_error}") from last_error
    raise RuntimeError("failed to launch WeChat")


def _open_wechat_app_with_driver(driver_call: DriverCall | None, wait: float) -> bool:
    if driver_call is None:
        return False

    for bundle in WECHAT_BUNDLES:
        try:
            print(f">> [WeChatCollect] hmdriver2 启动微信: bundle={bundle}")
            result = driver_call(
                f"Driver.force_start_app({bundle})",
                lambda driver: driver.force_start_app(bundle),
            )
            if result is False:
                raise RuntimeError("driver returned False")
            if wait > 0:
                time.sleep(wait)
            print(f">> [WeChatCollect] hmdriver2 启动命令完成: bundle={bundle}")
            return True
        except Exception as ex:
            print(f">> [WeChatCollect] hmdriver2 启动失败，尝试下一入口: bundle={bundle}, error={ex}")
    return False


def _run_driver_preferred(
    driver_call: DriverCall | None,
    label: str,
    operation: Callable[[Any], Any],
) -> bool:
    if driver_call is None:
        return False
    try:
        result = driver_call(label, operation)
        if result is False:
            raise RuntimeError("driver returned False")
        return True
    except Exception as ex:
        print(f">> [WeChatCollect] hmdriver2 操作失败，回退 HDC: {label}: {ex}")
        return False


def _wechat_ability_candidates(prefix: list[str], bundle: str) -> list[str]:
    """按优先级返回微信入口 Ability：先用 bm dump 发现，再使用内置候选兜底。"""

    abilities: list[str] = []
    discovered = _discover_main_ability(prefix, bundle)
    if discovered:
        abilities.append(discovered)
    abilities.extend(WECHAT_ABILITY_CANDIDATES.get(bundle, ()))
    return _dedupe_texts(abilities)


def _discover_main_ability(prefix: list[str], bundle: str) -> str:
    """通过 bundle manager dump 读取入口 Ability；失败时返回空串，由静态候选继续兜底。"""

    try:
        result = _run_hdc(prefix + ["shell", "bm", "dump", "-n", bundle])
    except Exception:
        return ""
    return _extract_main_ability(result.stdout + "\n" + result.stderr)


def _extract_main_ability(text: str) -> str:
    """从 bm dump 文本中提取入口 Ability，兼容不同系统版本的字段名。"""

    field_names = (
        "mainAbility",
        "mainAbilityName",
        "mainElementName",
        "mainElement",
        "launchAbility",
        "launcherAbility",
    )
    for raw_line in text.splitlines():
        line = raw_line.strip().strip(",")
        for field in field_names:
            if field not in line:
                continue
            value = _ability_value_after_separator(line)
            if value:
                return value
    return ""


def _ability_value_after_separator(line: str) -> str:
    for separator in (":", "="):
        if separator not in line:
            continue
        value = line.split(separator, 1)[1].strip().strip('",\'')
        if value:
            candidate = value.split()[0].strip().strip('",\'')
            if _looks_like_ability_name(candidate):
                return candidate
    return ""


def _looks_like_ability_name(value: str) -> bool:
    if not value or not any(char.isalpha() for char in value):
        return False
    return all(char.isalnum() or char in "._$" for char in value)


def _dedupe_texts(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        text = value.strip()
        if not text or text in seen:
            continue
        seen.add(text)
        result.append(text)
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
