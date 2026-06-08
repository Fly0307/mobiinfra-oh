#!/usr/bin/env python3
"""生成可导入设备的 Workflow 源级 mock 数据。

默认输出只包含 workflows/daily-log 源文件。
profile-consolidation 等派生目录由 App 内分析流程自行生成。
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable


# 这两条规则对齐 App 侧 DataManagerUtils.ets 的解析逻辑，避免 mock 文件格式
# 漂移到 App 管线无法识别的状态。
DAILY_LOG_METADATA_PATTERN = re.compile(r"^<!-- DAILY_LOG_METADATA\n([\s\S]*?)\n-->\n*")
NUMBERED_ENTRY_PATTERN = re.compile(r"(?:^|\n\s*\n)(\d+)\.\s+([\s\S]*?)(?=\n\s*\n\d+\.\s+|$)")
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_ROOT = REPO_ROOT / "mock" / "workflows-source"
DEFAULT_LLM_API_URL = "http://123.60.91.241:9003/v1"
DEFAULT_LLM_API_KEY = ""
DEFAULT_LLM_MODEL = "Qwen3.5-35B-A3B"
DEFAULT_LLM_BATCH_SIZE = 10
# 当前 Qwen3.5 服务的上下文上限是 32768；如果 output tokens 也设为 32768，
# 非空 prompt 会导致服务端 400。默认留出输入预算，避免批量生成中断。
DEFAULT_LLM_MAX_TOKENS = 16384
DEFAULT_LLM_TOP_P = 0.8
DEFAULT_LLM_PRESENCE_PENALTY = 1.5
DEFAULT_LLM_TOP_K = 20
DEFAULT_LLM_ENABLE_THINKING = False

JsonMap = dict[str, Any]
RequestJson = Callable[[str, str, str, list[JsonMap], float, int], JsonMap]


@dataclass(frozen=True)
class DailyLogFixture:
    """App 侧 consolidation 之前的源级 daily-log 文档。"""

    date: str
    file_name: str
    description: str
    scene_id: int
    entries: tuple[str, ...]


# 内置 fixtures 保持确定性，便于重复测试；更大或更细分领域的数据
# 可通过 --llm-count 追加生成。
FIXTURES: tuple[DailyLogFixture, ...] = (
    DailyLogFixture(
        date="2026-06-01",
        file_name="me.ele.eleme__basic-gui-task.md",
        description="查看饿了么上的用户订单信息",
        scene_id=1,
        entries=(
            "当前页面显示了三个外卖订单。第一单来自“馋湘味·新鲜爆炒(莲花南路店)”，单人自由套餐实付14.99元；第二单来自“京德顺·北京烤鸭(颛兴路店)”，套餐共2件实付53.6元；第三单来自“叮咚买菜(剑川站)”，购买土豆、香菜和鸡蛋等商品，总价48.1元。",
            "当前页面显示的是饿了么个人中心，包含“我的订单”“收货地址”“我的钱包”等入口，但没有直接展示具体订单列表，需要进入我的订单后查看外卖消费明细。",
            "当前页面展示“馋湘味·新鲜爆炒(莲花南路店)”订单详情，订单已送达上海交通大学闵行校区软件学院，商品为单人自由套餐送福利，实付14.99元，优惠15.31元。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-01",
        file_name="com.alipay.mobile.client__basic-gui-task.md",
        description="查看支付宝上的用户账单信息",
        scene_id=0,
        entries=(
            "当前支付宝账单页面显示了多条消费记录：上海地铁出行扣款4元，瑞幸咖啡消费18.8元，盒马鲜生购物付款76.5元，记录按时间倒序排列。",
            "当前账单详情展示一笔淘宝购物付款，商户为天猫超市，金额129.9元，付款方式为余额宝，备注中包含日用品和厨房纸巾。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-02",
        file_name="com.tencent.wechat__basic-gui-task__小赵.md",
        description="收集指定微信用户近3页的聊天记录",
        scene_id=3,
        entries=(
            "当前微信聊天界面显示“小赵”提醒周五下午确认项目演示材料，重点检查采集记录、日志整理和首页画像三处页面的展示效果。",
            "当前聊天记录中“小赵”发送了一条关于外卖发票的消息，说明上周饿了么订单需要补充抬头信息，并提到如果系统能自动汇总会更方便。",
            "当前页面显示“小赵”讨论周末出行计划，提到想去苏州看展并比较高铁和自驾两种方案，预计周六早上出发。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-02",
        file_name="com.sina.weibo.stage__basic-gui-task.md",
        description="查看微博热搜中排名第一的新闻。",
        scene_id=5,
        entries=(
            "当前微博热搜第一条与新能源汽车发布会有关，话题讨论集中在续航、智能驾驶和价格区间，评论区用户主要关注补贴政策和交付时间。",
            "当前微博页面展示一条电影节相关热搜，内容提到多位演员出席红毯，用户讨论服装造型、获奖预测和直播观看入口。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-03",
        file_name="com.xingin.xhs_hos__basic-gui-task.md",
        description="查看小红书上的用户浏览记录",
        scene_id=5,
        entries=(
            "当前小红书浏览记录包含一篇咖啡店探店笔记，地点在徐汇滨江，内容提到手冲咖啡、安静座位和适合周末阅读。",
            "当前页面显示一篇收纳改造笔记，作者分享桌面理线、文件夹分类和小户型储物盒选择，评论区讨论性价比。",
            "当前浏览记录中有一篇苏州两日游攻略，推荐平江路、苏州博物馆和金鸡湖夜景，并提醒周末需要提前预约。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-03",
        file_name="com.sankuai.dianping__basic-gui-task.md",
        description="查看大众点评上的用户订单记录",
        scene_id=4,
        entries=(
            "当前大众点评订单页面显示一笔理发店消费，店铺为“青木造型”，项目为男士剪发，实付68元，订单状态为已完成。",
            "当前页面展示一笔餐厅团购券订单，店铺为“南翔小笼”，套餐包含小笼包和牛肉粉丝汤，实付42.8元，待到店使用。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-04",
        file_name="com.ctrip.harmony__basic-gui-task.md",
        description="查看携程上的用户全部订单",
        scene_id=6,
        entries=(
            "当前携程订单页面显示一张上海到苏州的高铁票订单，出发时间为周六上午9点12分，二等座，订单状态为已出票。",
            "当前页面显示一笔酒店预订，酒店位于苏州观前街附近，入住一晚，含双早，订单状态为待入住，页面提示可在入住前免费取消。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-04",
        file_name="com.sankuai.meituan__basic-gui-task.md",
        description="查看美团上的用户订单记录",
        scene_id=4,
        entries=(
            "当前美团订单页面显示一笔生鲜超市订单，商家为“盒马鲜生”，商品包含蓝莓、鸡胸肉和气泡水，实付96.7元，订单状态为已完成。",
            "当前页面展示一笔电影票订单，影院为上海影城，影片为科幻片夜场，两张票共96元，座位在7排中间区域。",
            "当前美团页面显示一笔洗衣服务订单，项目为两件衬衫和一件外套清洗，实付58元，状态为配送中。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-04",
        file_name="com.jd.harmony__basic-gui-task.md",
        description="查看京东上的用户订单记录",
        scene_id=0,
        entries=(
            "当前京东订单页面显示一笔数码配件订单，包含USB-C扩展坞、手机支架和数据线，实付219元，订单状态为已签收。",
            "当前页面展示一笔家清用品订单，商品包含洗衣液、厨房湿巾和垃圾袋，使用满减后实付83.6元。",
            "当前京东售后页面显示一笔键盘退换货申请，原因是按键回弹异常，客服提示等待上门取件。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-05",
        file_name="com.tencent.wechat__basic-gui-task__产品群.md",
        description="收集微信群近3页的聊天记录",
        scene_id=3,
        entries=(
            "当前微信群聊中团队讨论数据归家首页，建议把用户画像、最近采集和待处理日志放在同一屏内，减少跳转。",
            "当前聊天记录里有人反馈 Workflow 日志页面在窄屏下列表占用空间偏多，希望文件列表和当前文件信息支持折叠。",
            "当前群聊中测试同学提到 mock daily-log 数据应只覆盖原始输入，派生索引和分组需要由 App 自己生成。",
            "当前页面显示群成员在讨论 HDC 导入脚本，建议默认使用 bundle alias 路径，避免直接依赖 /data/app/el2 物理目录。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-05",
        file_name="com.tencent.video.hm__basic-gui-task.md",
        description="查看腾讯视频上的用户观看记录",
        scene_id=2,
        entries=(
            "当前腾讯视频观看历史显示用户最近观看了一部纪录片，主题为城市更新，进度停留在第2集18分钟。",
            "当前页面展示一部悬疑剧观看记录，已看到第7集，系统推荐继续观看下一集和幕后花絮。",
            "当前观看记录中包含一场篮球比赛回放，用户看到第四节还剩6分钟的位置。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-05",
        file_name="tv.danmaku.bili__basic-gui-task.md",
        description="查看哔哩哔哩上的用户浏览记录",
        scene_id=2,
        entries=(
            "当前哔哩哔哩历史记录包含一个 HarmonyOS ArkTS 教程视频，内容讲解 ListItem swipeAction 和状态管理。",
            "当前页面显示一条咖啡测评视频浏览记录，标题提到办公室手冲器具选择和浅烘豆风味。",
            "当前浏览记录中有一条旅行 vlog，内容是苏州周末路线，包含博物馆预约、园林游览和夜景拍摄。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-06",
        file_name="com.autonavi.minimap__basic-gui-task.md",
        description="查看高德地图上的用户出行记录",
        scene_id=6,
        entries=(
            "当前高德地图路线页面显示从上海交通大学闵行校区到虹桥火车站，推荐地铁5号线转2号线，预计用时62分钟。",
            "当前页面展示一条打车行程记录，起点为徐汇滨江，终点为静安寺，费用约42元，晚高峰预计堵车15分钟。",
            "当前收藏地点列表包含苏州博物馆、平江路和金鸡湖，备注为周末两日游备选路线。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-06",
        file_name="com.taobao.taobao_hm__basic-gui-task.md",
        description="查看淘宝上的用户订单记录",
        scene_id=0,
        entries=(
            "当前淘宝订单页面显示一笔桌面收纳订单，包含透明文件盒、磁吸理线器和便签架，合计67.8元。",
            "当前页面展示一笔服饰订单，商品为白色防晒衬衫和轻薄运动短裤，店铺承诺48小时内发货。",
            "当前淘宝物流页面显示咖啡滤纸和手冲壶已经到达上海转运中心，预计明天派送。",
        ),
    ),
    DailyLogFixture(
        date="2026-06-06",
        file_name="com.huawei.health__basic-gui-task.md",
        description="查看运动健康上的用户记录",
        scene_id=4,
        entries=(
            "当前运动健康页面显示今天步数为8532步，活动热量312千卡，上午有一次30分钟快走记录。",
            "当前睡眠页面显示昨晚睡眠7小时12分钟，深睡比例偏低，App 建议提前放下手机并保持固定作息。",
            "当前运动记录显示一次室内骑行训练，持续42分钟，平均心率128，系统标记为有氧耐力训练。",
        ),
    ),
    # 保留一条真实 LLM 生成样例，确保默认 mock 也覆盖 LLM 输出的文件命名和内容形态。
    DailyLogFixture(
        date="2026-06-08",
        file_name="com.meituan.waimai__basic-gui-task__llm-takeout-美团外卖.md",
        description="查看外卖和餐饮订单信息",
        scene_id=1,
        entries=(
            "用户于中午12点35分在‘味千拉面’下单了一份招牌豚骨面套餐，订单金额42.5元，已使用满减优惠，预计13点送达写字楼前台。",
        ),
    ),
)


def daily_log_content(fixture: DailyLogFixture) -> str:
    """按 WorkflowRunner 的真实 Markdown 格式渲染一个 fixture。"""

    metadata = {
        "workflow_metadata": {
            "name": "basic-gui-task",
            "description": fixture.description,
            "task_scene_id": fixture.scene_id,
        },
        "latest_entry_index": len(fixture.entries),
    }
    body = "\n\n".join(f"{index + 1}. {entry}" for index, entry in enumerate(fixture.entries))
    return "<!-- DAILY_LOG_METADATA\n" + json.dumps(metadata, ensure_ascii=False, indent=2) + "\n-->\n\n" + body + "\n"


def normalize_chat_completion_url(api_url: str) -> str:
    """接收常见 OpenAI-compatible 地址，并归一化为 chat completions 端点。"""

    value = api_url.strip().rstrip("/")
    if value.endswith("/v1/models"):
        return value[: -len("/models")] + "/chat/completions"
    if value.endswith("/models"):
        return value[: -len("/models")] + "/chat/completions"
    if value.endswith("/v1"):
        return value + "/chat/completions"
    if value.endswith("/chat/completions"):
        return value
    return value + "/v1/chat/completions"


def default_request_json(
    endpoint: str,
    api_key: str,
    model: str,
    messages: list[JsonMap],
    temperature: float,
    timeout: int,
) -> JsonMap:
    """发起一次 OpenAI-compatible chat completion 请求并返回 JSON。"""

    payload = {
        "model": model,
        "messages": messages,
        "max_tokens": DEFAULT_LLM_MAX_TOKENS,
        "temperature": temperature,
        "top_p": DEFAULT_LLM_TOP_P,
        "presence_penalty": DEFAULT_LLM_PRESENCE_PENALTY,
        # OpenAI Python SDK 的 extra_body 会合并到 HTTP JSON 顶层；
        # 这里直接发顶层字段，确保 Qwen3.5 服务端能关闭 thinking 输出。
        "top_k": DEFAULT_LLM_TOP_K,
        "chat_template_kwargs": {"enable_thinking": DEFAULT_LLM_ENABLE_THINKING},
    }
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = "Bearer " + api_key
    request = urllib.request.Request(endpoint, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.URLError as exc:
        raise RuntimeError(f"LLM request failed: {exc}") from exc


def normalize_domain(value: str) -> str:
    """把中英文领域别名归一化为生成器内部稳定 key。"""

    normalized = value.strip().lower()
    aliases = {
        "eat": "takeout",
        "food": "takeout",
        "外卖": "takeout",
        "购物": "shopping",
        "消费": "shopping",
        "聊天": "chat",
        "社交": "social",
        "出行": "travel",
        "旅行": "travel",
        "生活": "life",
        "娱乐": "entertainment",
    }
    return aliases.get(normalized, normalized or "life")


def domain_scene_id(domain: str) -> int:
    """把 mock 数据领域映射到 App 分析使用的 Workflow sceneId。"""

    mapping = {
        "shopping": 0,
        "takeout": 1,
        "entertainment": 2,
        "chat": 3,
        "life": 4,
        "social": 5,
        "travel": 6,
    }
    return mapping.get(normalize_domain(domain), 4)


def domain_description(domain: str) -> str:
    """为 LLM 生成的 daily-log 文件构造 metadata.description。"""

    mapping = {
        "shopping": "查看购物和账单记录",
        "takeout": "查看外卖和餐饮订单信息",
        "entertainment": "查看娱乐内容浏览记录",
        "chat": "收集聊天记录摘要",
        "life": "查看生活服务记录",
        "social": "查看社交内容浏览记录",
        "travel": "查看出行和旅行订单",
    }
    return mapping.get(normalize_domain(domain), "查看生活记录")


def default_package_for_domain(domain: str) -> str:
    """当模型没有返回 package_name 时选择一个接近真实的兜底包名。"""

    mapping = {
        "shopping": "com.alipay.mobile.client",
        "takeout": "me.ele.eleme",
        "entertainment": "tv.danmaku.bili",
        "chat": "com.tencent.wechat",
        "life": "com.sankuai.dianping",
        "social": "com.xingin.xhs_hos",
        "travel": "com.ctrip.harmony",
    }
    return mapping.get(normalize_domain(domain), "com.example.mock")


def safe_file_token(value: str) -> str:
    """清理文件名片段中的非法字符，同时保留可读的中文。"""

    text = value.strip()
    if not text:
        return "mock"
    text = re.sub(r"[\\/:*?\"<>|\s]+", "_", text)
    text = re.sub(r"_+", "_", text).strip("_")
    return text or "mock"


def normalize_mock_date(value: str, fallback_index: int) -> str:
    """确保生成日期落在 YYYY-MM-DD 目录中，便于 App 扫描。"""

    candidate = value.strip()[:10]
    if re.match(r"^\d{4}-\d{2}-\d{2}$", candidate):
        return candidate
    day = 5 + (fallback_index % 8)
    return f"2026-06-{day:02d}"


def build_llm_messages(count: int, domains: list[str]) -> list[JsonMap]:
    """提示模型生成原始页面摘要，而不是派生事实或索引结果。"""

    domain_text = ", ".join(domains)
    system = (
        "你是一个 Workflow daily-log mock 数据生成器。"
        "只输出严格 JSON，不要 markdown，不要解释。"
        "每条数据必须像真实 VLM 页面摘要，使用自然语言描述页面上可见的信息。"
    )
    user = (
        f"请生成 {count} 条 mock daily-log 原始条目，领域限定为：{domain_text}。\n"
        "输出 JSON 格式：{\"entries\":[{\"domain\":\"takeout|shopping|chat|social|travel|life|entertainment\","
        "\"source_app\":\"应用名\",\"package_name\":\"包名\",\"date\":\"YYYY-MM-DD\",\"text\":\"自然语言页面摘要\"}]}。\n"
        "要求：日期分布在 2026-06-05 到 2026-06-12；text 不要编号，不要 markdown；"
        "内容要覆盖订单、消费、聊天、内容浏览、出行或生活服务等可被后续分析拆分成事实的原始信息。"
    )
    return [
        {"role": "system", "content": system},
        {"role": "user", "content": user},
    ]


def extract_json_object(raw: str) -> JsonMap:
    """从模型输出中提取第一个可解析 JSON 对象。

    Qwen 类模型即使被要求输出严格 JSON，也可能带上简短思考文本或尾随内容。
    这里扫描可解码对象，而不是简单取第一和最后一个大括号。
    """

    text = raw.strip()
    if text.startswith("```"):
        text = re.sub(r"^```(?:json)?\s*", "", text)
        text = re.sub(r"\s*```$", "", text)
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char != "{":
            continue
        try:
            value, _ = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(value, dict):
            return value
    raise json.JSONDecodeError("No JSON object found", text, 0)


def chat_response_content(response: JsonMap) -> str:
    """读取 OpenAI-compatible 或简化 text completion 响应中的正文。"""

    choices = response.get("choices")
    if isinstance(choices, list) and choices:
        first = choices[0]
        if isinstance(first, dict):
            message = first.get("message")
            if isinstance(message, dict) and isinstance(message.get("content"), str):
                return message["content"]
            if isinstance(first.get("text"), str):
                return first["text"]
    raise RuntimeError("LLM response does not contain choices[0].message.content")


def generate_llm_entries(
    total_entries: int,
    domains: list[str],
    api_url: str,
    api_key: str,
    model: str,
    request_json: RequestJson = default_request_json,
    batch_size: int = DEFAULT_LLM_BATCH_SIZE,
    temperature: float = 0.7,
    timeout: int = 120,
) -> list[JsonMap]:
    """循环调用 LLM，直到拿到指定数量的有效原始条目。"""

    endpoint = normalize_chat_completion_url(api_url)
    normalized_domains = [normalize_domain(domain) for domain in domains if normalize_domain(domain)]
    if not normalized_domains:
        normalized_domains = ["takeout", "shopping", "chat", "social", "travel", "life", "entertainment"]
    entries: list[JsonMap] = []
    attempts = 0
    max_attempts = max(3, (total_entries // max(1, batch_size)) + 4)
    while len(entries) < total_entries and attempts < max_attempts:
        attempts += 1
        count = min(batch_size, total_entries - len(entries))
        response = request_json(
            endpoint,
            api_key,
            model,
            build_llm_messages(count, normalized_domains),
            temperature,
            timeout,
        )
        payload = extract_json_object(chat_response_content(response))
        raw_entries = payload.get("entries")
        if not isinstance(raw_entries, list):
            raise RuntimeError("LLM JSON must contain an entries array")
        for item in raw_entries:
            if not isinstance(item, dict):
                continue
            text = str(item.get("text", "")).strip()
            if not text:
                continue
            domain = normalize_domain(str(item.get("domain", normalized_domains[0])))
            if domain not in normalized_domains:
                domain = normalized_domains[len(entries) % len(normalized_domains)]
            entries.append({
                "domain": domain,
                "source_app": str(item.get("source_app", "")).strip(),
                "package_name": str(item.get("package_name", "")).strip() or default_package_for_domain(domain),
                "date": normalize_mock_date(str(item.get("date", "")), len(entries)),
                "text": text,
            })
            if len(entries) >= total_entries:
                break
    if len(entries) < total_entries:
        raise RuntimeError(f"LLM returned {len(entries)} valid entries, expected {total_entries}")
    return entries[:total_entries]


def fixtures_from_generated_entries(entries: list[JsonMap]) -> list[DailyLogFixture]:
    """把模型生成的原始条目按日期、包名和领域分组成 daily-log 文档。"""

    grouped: dict[tuple[str, str, str], list[str]] = {}
    metadata: dict[tuple[str, str, str], tuple[str, int]] = {}
    for item in entries:
        domain = normalize_domain(str(item.get("domain", "life")))
        date = str(item.get("date", "2026-06-05"))[:10]
        package_name = safe_file_token(str(item.get("package_name", "")) or default_package_for_domain(domain))
        source_app = safe_file_token(str(item.get("source_app", "")) or domain)
        key = (date, package_name, domain)
        grouped.setdefault(key, []).append(str(item.get("text", "")).strip())
        metadata[key] = (source_app, domain_scene_id(domain))

    fixtures: list[DailyLogFixture] = []
    for key in sorted(grouped.keys()):
        date, package_name, domain = key
        source_app, scene_id = metadata[key]
        file_name = f"{package_name}__basic-gui-task__llm-{safe_file_token(domain)}-{source_app}.md"
        fixtures.append(DailyLogFixture(
            date=date,
            file_name=file_name,
            description=domain_description(domain),
            scene_id=scene_id,
            entries=tuple(grouped[key]),
        ))
    return fixtures


def generate_llm_fixtures(
    total_entries: int,
    domains: list[str],
    api_url: str = DEFAULT_LLM_API_URL,
    api_key: str = DEFAULT_LLM_API_KEY,
    model: str = DEFAULT_LLM_MODEL,
    request_json: RequestJson = default_request_json,
    batch_size: int = DEFAULT_LLM_BATCH_SIZE,
    temperature: float = 0.7,
    timeout: int = 120,
) -> list[DailyLogFixture]:
    """通过配置的 LLM 服务生成额外 daily-log fixtures。"""

    if total_entries <= 0:
        return []
    entries = generate_llm_entries(
        total_entries=total_entries,
        domains=domains,
        api_url=api_url,
        api_key=api_key,
        model=model,
        request_json=request_json,
        batch_size=batch_size,
        temperature=temperature,
        timeout=timeout,
    )
    return fixtures_from_generated_entries(entries)


def run_summary_for_fixture(fixture: DailyLogFixture, run_index: int) -> dict[str, Any]:
    """创建可选的轻量 run_summary.json，用于图片引用相关测试。"""

    run_name = f"{fixture.date.replace('-', '')}-{100000 + run_index:06d}-basic-gui-task"
    daily_log_path = (
        "/data/storage/el2/base/haps/entry/files/workflows/daily-log/"
        + fixture.date
        + "/"
        + fixture.file_name
    )
    run_dir = "/data/storage/el2/base/haps/entry/files/workflows/runs/" + run_name
    first_entry = fixture.entries[0]
    return {
        "workflow_file": "/data/storage/el2/base/haps/entry/files/workflows/configs/mock_" + fixture.file_name.replace(".md", ".json"),
        "run_dir": run_dir,
        "context": {},
        "status": "success",
        "steps": {
            "1": {
                "step_id": "1",
                "status": "success",
                "started_at": 1780500000 + run_index * 100,
                "finished_at": 1780500002 + run_index * 100,
                "duration_sec": 2,
                "output": {
                    "step_dir": run_dir + "/steps/1",
                    "task_description": fixture.description,
                    "planner_task_description": fixture.description,
                    "app_name": fixture.file_name.split("__")[0],
                    "package_name": fixture.file_name.split("__")[0],
                    "device": "Harmony",
                    "mode": "planner_only",
                },
            },
            "2": {
                "step_id": "2",
                "status": "success",
                "started_at": 1780500003 + run_index * 100,
                "finished_at": 1780500004 + run_index * 100,
                "duration_sec": 1,
                "output": {
                    "step_dir": run_dir + "/steps/2",
                    "action": "screenshot",
                    "device": "Harmony",
                    "image_path": "mock/screenshots/" + fixture.file_name.replace(".md", ".jpg"),
                    "width": 628,
                    "height": 1380,
                    "file_name": fixture.file_name.replace(".md", ".jpg"),
                },
            },
            "3": {
                "step_id": "3",
                "status": "success",
                "started_at": 1780500005 + run_index * 100,
                "finished_at": 1780500006 + run_index * 100,
                "duration_sec": 1,
                "output": {
                    "step_dir": run_dir + "/steps/3",
                    "tool_name": "vlm_qa",
                    "mode": "summary",
                    "question": "Mock summary for source-level workflow data validation",
                    "response": first_entry,
                    "deferred": False,
                    "daily_log_path": daily_log_path,
                },
            },
        },
    }


def generate_mock(
    output_root: Path | str = DEFAULT_OUTPUT_ROOT,
    include_runs: bool = False,
    clean: bool = True,
    llm_fixtures: tuple[DailyLogFixture, ...] = (),
) -> dict[str, int]:
    """把源级 mock 文件写入磁盘。

    默认输出只包含 daily-log 源数据。可选 run summaries 用于测试图片引用；
    profile/index 等派生输出必须仍由 App 自己生成。
    """

    root = Path(output_root)
    if clean and root.exists():
        shutil.rmtree(root)
    daily_root = root / "daily-log"
    daily_root.mkdir(parents=True, exist_ok=True)
    fixtures = FIXTURES + llm_fixtures

    for fixture in fixtures:
        target = daily_root / fixture.date / fixture.file_name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(daily_log_content(fixture), encoding="utf-8")

    run_files = 0
    if include_runs:
        runs_root = root / "runs"
        for index, fixture in enumerate(fixtures[:3], start=1):
            run_name = f"{fixture.date.replace('-', '')}-{100000 + index:06d}-basic-gui-task"
            target = runs_root / run_name / "run_summary.json"
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(
                json.dumps(run_summary_for_fixture(fixture, index), ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            run_files += 1

    return {
        "daily_log_files": len(fixtures),
        "run_files": run_files,
        "entry_count": sum(len(fixture.entries) for fixture in fixtures),
    }


def parse_numbered_entries(body: str) -> list[tuple[int, str]]:
    """解析 App 实际消费的编号 Markdown 条目。"""

    entries: list[tuple[int, str]] = []
    for match in NUMBERED_ENTRY_PATTERN.finditer(body.strip()):
        text = match.group(2).strip()
        if text:
            entries.append((int(match.group(1)), text))
    return entries


def validate_mock(output_root: Path | str = DEFAULT_OUTPUT_ROOT) -> dict[str, Any]:
    """校验 mock 数据仍是源级数据，并且可被 App 解析。"""

    root = Path(output_root)
    errors: list[str] = []
    daily_files = sorted((root / "daily-log").glob("*/*.md"))
    run_files = sorted((root / "runs").glob("*/run_summary.json")) if (root / "runs").exists() else []
    if (root / "profile-consolidation").exists():
        errors.append("profile-consolidation must not be part of source mock data")
    if not daily_files:
        errors.append("daily-log source files are missing")

    entry_count = 0
    for path in daily_files:
        relative = path.relative_to(root).as_posix()
        content = path.read_text(encoding="utf-8")
        metadata_match = DAILY_LOG_METADATA_PATTERN.match(content)
        if metadata_match is None:
            errors.append(f"{relative}: missing DAILY_LOG_METADATA block")
            continue
        try:
            metadata = json.loads(metadata_match.group(1))
        except json.JSONDecodeError as exc:
            errors.append(f"{relative}: invalid metadata JSON: {exc}")
            continue
        workflow_metadata = metadata.get("workflow_metadata")
        if not isinstance(workflow_metadata, dict):
            errors.append(f"{relative}: workflow_metadata must be an object")
        latest_entry_index = metadata.get("latest_entry_index")
        body = content[metadata_match.end():]
        entries = parse_numbered_entries(body)
        entry_count += len(entries)
        if latest_entry_index != len(entries):
            errors.append(f"{relative}: latest_entry_index={latest_entry_index} but numbered entries={len(entries)}")
        if len(entries) == 0:
            errors.append(f"{relative}: no numbered entries")

    return {
        "errors": errors,
        "daily_log_files": len(daily_files),
        "run_files": len(run_files),
        "entry_count": entry_count,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="生成源级 Workflow mock 数据。")
    parser.add_argument("--output-root", default=str(DEFAULT_OUTPUT_ROOT), help="输出根目录，默认 mock/workflows-source")
    parser.add_argument("--include-runs", action="store_true", help="同时生成轻量 runs/run_summary.json 文件")
    parser.add_argument("--llm-count", type=int, default=0, help="通过 LLM 追加生成的原始条目数量")
    parser.add_argument(
        "--llm-domains",
        default="takeout,shopping,chat,social,travel,life,entertainment",
        help="逗号分隔的 LLM 生成领域，例如 takeout,travel,chat",
    )
    parser.add_argument("--llm-api-url", default=DEFAULT_LLM_API_URL)
    parser.add_argument("--llm-api-key", default=DEFAULT_LLM_API_KEY)
    parser.add_argument("--llm-model", default=DEFAULT_LLM_MODEL)
    parser.add_argument("--llm-batch-size", type=int, default=DEFAULT_LLM_BATCH_SIZE)
    parser.add_argument("--llm-temperature", type=float, default=0.7)
    parser.add_argument("--llm-timeout", type=int, default=120)
    parser.add_argument("--no-clean", action="store_true", help="生成前保留已有输出文件")
    parser.add_argument("--validate-only", action="store_true", help="只校验已有 mock 输出，不重新生成")
    parser.add_argument("--quiet", action="store_true", help="只打印校验错误")
    args = parser.parse_args()

    output_root = Path(args.output_root)
    if not args.validate_only:
        llm_fixtures: tuple[DailyLogFixture, ...] = ()
        if args.llm_count > 0:
            domains = [domain.strip() for domain in args.llm_domains.split(",") if domain.strip()]
            generated = generate_llm_fixtures(
                total_entries=args.llm_count,
                domains=domains,
                api_url=args.llm_api_url,
                api_key=args.llm_api_key,
                model=args.llm_model,
                batch_size=max(1, args.llm_batch_size),
                temperature=args.llm_temperature,
                timeout=args.llm_timeout,
            )
            llm_fixtures = tuple(generated)
            if not args.quiet:
                print(
                    "Generated LLM fixtures: "
                    f"entries={args.llm_count}, files={len(llm_fixtures)}, "
                    f"model={args.llm_model}, endpoint={normalize_chat_completion_url(args.llm_api_url)}"
                )
        summary = generate_mock(
            output_root,
            include_runs=args.include_runs,
            clean=not args.no_clean,
            llm_fixtures=llm_fixtures,
        )
        if not args.quiet:
            print(
                "Generated Workflow mock sources: "
                f"daily_log_files={summary['daily_log_files']}, "
                f"entries={summary['entry_count']}, "
                f"run_files={summary['run_files']}, "
                f"output={output_root}"
            )

    validation = validate_mock(output_root)
    if validation["errors"]:
        for error in validation["errors"]:
            print("ERROR: " + error)
        return 1
    if not args.quiet:
        print(
            "Validated Workflow mock sources: "
            f"daily_log_files={validation['daily_log_files']}, "
            f"entries={validation['entry_count']}, "
            f"run_files={validation['run_files']}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
