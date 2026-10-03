#!/usr/bin/env python3
"""微信采集模块的统一配置。

解析器、设备采集和服务入口都从本模块读取默认值，避免各层各自维护配置
导致行为和 UI 提示漂移。
"""

DEFAULT_DAYS = 7
DEFAULT_MAX_CONTACTS = 10
DEFAULT_SWIPE_SPEED = 2000
DEFAULT_HISTORY_SWIPE_RATIO = 0.4
DEFAULT_STABLE_SWIPES = 3
DEFAULT_MAX_HISTORY_SWIPES = 80
DEFAULT_WAIT = 1.0
DEFAULT_MAX_LIST_SWIPES = 20
DEFAULT_HDC_TIMEOUT = 20
BOUNDARY_OVERLAP_RATIO = 0.2

WECHAT_BUNDLES = ("com.tencent.wechat", "com.tencent.mm")
WECHAT_ABILITY_CANDIDATES = {
    "com.tencent.wechat": ("EntryAbility", "MainAbility", "WechatAbility", "WeChatMainAbility"),
    "com.tencent.mm": ("com.tencent.mm.ui.LauncherUI", ".ui.LauncherUI", "LauncherUI", "EntryAbility"),
}

SUPPORTED_MODES = {"recent_contacts", "target_contact"}


__all__ = [
    "BOUNDARY_OVERLAP_RATIO",
    "DEFAULT_DAYS",
    "DEFAULT_HDC_TIMEOUT",
    "DEFAULT_HISTORY_SWIPE_RATIO",
    "DEFAULT_MAX_CONTACTS",
    "DEFAULT_MAX_HISTORY_SWIPES",
    "DEFAULT_MAX_LIST_SWIPES",
    "DEFAULT_STABLE_SWIPES",
    "DEFAULT_SWIPE_SPEED",
    "DEFAULT_WAIT",
    "SUPPORTED_MODES",
    "WECHAT_ABILITY_CANDIDATES",
    "WECHAT_BUNDLES",
]
