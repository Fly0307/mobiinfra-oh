# 微信消息自动汇总模块设计

## 背景

当前 App 的“汇总”页已经通过 daily-log、数据归家、索引和分组服务展示整理后的采集记录。现有微信 Workflow 依赖截图和视觉模型总结，适合单次页面总结，但不适合稳定地批量采集最近联系人、按时间范围停止、合并相邻快照重复消息。

`/Users/zhaoxi/Documents/ipads/LlmAgent/Harmony/AUTOwechat` 已经提供基于 HarmonyOS `uitest dumpLayout` 的微信首页联系人解析、聊天页消息解析、历史滑动采集、最近 N 天过滤、相邻快照边界去重、JSON/Markdown 导出能力。新模块应复用这部分能力，并作为独立采集源接入当前 App。

## 目标

- 在“汇总”页面接入“微信消息自动汇总”采集源。
- 设置页提供开关；关闭时不显示汇总页微信模块，不影响现有主流程。
- 支持最近联系人模式：从微信首页滚动会话列表，尽量收集最近 N 个联系人，默认 10 个。
- 支持指定联系人模式：PC 侧 GUI Agent 先搜索并进入目标聊天页，然后用 UI dump 采集。
- 支持时间范围配置：默认值可在设置页配置，汇总页本次运行可临时覆盖，范围为 1 到 90 天。
- 保存原始 JSON/Markdown/dump 产物，便于追溯。
- 生成联系人级 daily-log，每个联系人一条 numbered entry，后续由现有数据归家链路拆分事实、建索引、进入“聊天”汇总。

## 非目标

- 第一版不做后台定时自动采集，只支持用户在汇总页手动触发。
- 第一版不在采集阶段调用云端模型生成自然语言摘要。
- 第一版不把 UI dump 解析逻辑写入 ArkTS。
- 第一版不改动现有 Workflow、AgentRouter、DataManager 的核心协议和主流程。
- 第一版不承诺能绕过微信版本或 HarmonyOS UI 树变化带来的解析差异；需要通过测试样例和错误提示降低风险。

## 总体架构

采用独立模块方案：

1. App 侧负责设置、入口、参数、触发、进度展示、结果保存和写 daily-log。
2. `hdc_server.py` 只新增受控接口和桥接逻辑，不承载微信解析细节。
3. 新增独立 Python 模块，例如 `entry/src/main/python/wechat_collect/`，迁入/复用 `AUTOwechat` 的解析与采集逻辑。
4. 设置关闭时，App 不显示入口，也不调用 PC 侧微信采集接口。

建议 PC 侧接口：

- `uidump`：通用 UI dump 接口，负责执行 `hdc shell uitest dumpLayout` 并返回或保存 UI 树。
- `wechat_collect`：微信采集入口，内部调用独立模块完成打开微信、联系人收集、聊天采集、结果导出。

## App 侧 UI

### 汇总页

- 保留“新增采集源”卡片。
- 点击“新增采集源”跳转到“设置页 > 数据采集”，用于集中管理采集源开关。
- 当“微信消息自动汇总”开关开启后，在“新增采集源/图库分析”附近显示微信采集卡片。

微信采集卡片包含：

- 模式切换：最近联系人 / 指定联系人。
- 时间范围：使用设置页默认值初始化，支持本次临时输入自定义天数。
- 最近联系人数量：使用设置页默认值初始化，支持本次临时修改。
- 指定联系人输入框：仅指定联系人模式显示。
- “开始采集”按钮。
- 最近一次采集状态、已采集联系人数量、原始产物入口或提示。
- 采集完成提示：可点击现有“同步”，也可在完成弹窗提供“立即同步”。

### 设置页

在“设置页 > 数据采集”新增“微信消息自动汇总”配置：

- 开关：启用/关闭微信采集源。
- 默认时间范围：支持快捷值和自定义天数，范围 1 到 90。
- 默认最近联系人数量：默认 10，范围 1 到 50。
- 高级参数折叠区：
  - `swipe_speed`，默认 2500。
  - `history_swipe_ratio`，默认 0.65。
  - `stable_swipes`，默认 3。
  - `max_history_swipes`，默认 80。
  - `wait`，默认 1.0 秒。
- 隐私提示：会保存微信原始消息 JSON/Markdown 和联系人级 daily-log。

## 采集流程

### 最近联系人模式

1. App 下发 `wechat_collect`，参数包括：
   - `mode=recent_contacts`
   - `max_contacts`
   - `days`
   - 滑动和等待参数
2. PC 侧打开微信，尽量回到会话首页。
3. 独立模块通过 UI dump 解析当前会话列表。
4. 向下滚动会话列表并去重，直到达到 `max_contacts`，或列表连续稳定，或达到滚动上限。
5. 依次点击联系人进入聊天页。
6. 聊天页按最近 N 天向历史方向滑动，保存快照。
7. 离线合并快照消息，按内容指纹和相邻页面边界重叠规则去重。
8. 返回首页，继续下一个联系人。
9. 输出聚合 JSON/Markdown 和单联系人 JSON/Markdown。

### 指定联系人模式

1. App 下发 `wechat_collect`，参数包括：
   - `mode=target_contact`
   - `target_contact`
   - `days`
   - 滑动和等待参数
2. PC 侧用现有 GUI Agent 搜索并进入目标联系人聊天页。
3. 进入聊天页后切换到 UI dump 历史滑动和消息合并。
4. 如果 GUI Agent 未能进入聊天页，整次失败并返回明确错误，不写 daily-log。

## 数据格式与落盘

PC 侧 `wechat_collect` 返回结构建议：

```json
{
  "status": "ok",
  "message": "collected 10 conversations",
  "run_id": "20260611-120000-wechat",
  "started_at": "2026-06-11T12:00:00",
  "finished_at": "2026-06-11T12:05:00",
  "mode": "recent_contacts",
  "days": 7,
  "contacts_requested": 10,
  "contacts_collected": 10,
  "conversations": [],
  "artifacts": {}
}
```

App 侧保存两类文件：

1. 原始产物：保存到 App 沙箱的 `workflows/wechat-collection/runs/<run_id>/`。
   - 聚合 JSON。
   - 聚合 Markdown。
   - 单联系人 JSON/Markdown。
   - UI dump 快照或快照路径索引。
2. daily-log：写入现有 `workflows/daily-log/YYYY-MM-DD/`。
   - 文件名建议：`com.tencent.mm__wechat_auto_summary__<run_id>.md`。
   - metadata 包含：
     - `task_scene_id=3`
     - `source_app=wechat`
     - `collector=wechat_auto_summary`
     - `run_id`
     - `mode`
     - `days`

daily-log 内容按每个联系人一条 numbered entry 写入，规则生成，不调用模型：

```text
1. 微信联系人「小赵」最近 7 天消息采集。采集时间范围：2026-06-04 至 2026-06-11；消息数：42。完整消息摘录：
- 2026-06-08 15:47｜我：我想要买一个 iPhone 17Pro
- 2026-06-08 15:47｜小赵：需要给妹妹买一些少儿读物
```

用户点击现有“同步”后，DataManager 按聊天场景继续拆事实、建索引，并在“汇总 > 聊天”记录中展示。

## 错误处理

- HDC 未连接：提示去设置页连接 HDC，不写文件。
- 微信打开失败：返回 `app_start` 错误，不写 daily-log。
- 最近联系人不足请求数量：保存已采集联系人，状态显示“已尽量采集 N 个”。
- 单个联系人采集失败：跳过该联系人，保留错误到 run summary，继续其他联系人。
- 指定联系人搜索失败：整次失败，不写 daily-log。
- 长请求超时：第一版提示到原始产物或运行状态查看；后续可扩展 run_id 轮询。
- 参数非法：App 侧先拦截，PC 侧再做防御性校验。

## 模块隔离

- Python 解析和采集逻辑放在独立模块，不直接堆进 `hdc_server.py`。
- `hdc_server.py` 只负责参数校验、HDC 目标准备、接口分发和错误包装。
- App 侧新增的设置状态只控制微信模块，不影响图库分析、Workflow、聊天 Agent、DataManager 同步。
- 关闭开关后，汇总页不显示微信采集卡片；已有 daily-log 和原始产物不自动删除。

## 测试与验收

### Python 单元测试

迁入并扩展 `AUTOwechat` 现有测试，覆盖：

- 首页联系人解析。
- 聊天标题解析。
- 文本消息、图片/文件占位消息解析。
- 微信时间锚点解析。
- 最近 N 天过滤。
- 历史快照合并。
- 相邻快照边界去重。
- Markdown 输出。
- 最近联系人列表滚动去重的纯逻辑。

### `hdc_server.py` 测试

新增不依赖真机的测试，覆盖：

- `uidump` 参数校验和错误返回。
- `wechat_collect` 参数范围校验。
- 独立模块异常时的错误包装。
- 未启用微信模块时不影响现有 `/api/workflow` action。

### ArkTS 测试与检查

- 设置默认值和参数范围校验。
- 开关关闭时汇总页不显示微信模块。
- “新增采集源”跳转到设置页数据采集。
- 开关开启后汇总页显示微信模块，并使用默认参数初始化。
- `git diff --check`。
- 可用时运行 Hvigor test；真机采集仍需 DevEco/HDC 环境人工验证。

### 真机验收

- 开关关闭：汇总页不显示微信模块。
- 点击“新增采集源”：进入设置页数据采集，可看到微信开关。
- 开关开启：汇总页显示微信采集卡片。
- 最近联系人模式：从微信首页滚动收集，尽量采集配置数量的联系人。
- 指定联系人模式：GUI Agent 搜索进入目标聊天页后，UI dump 采集消息。
- 采集完成：原始 JSON/Markdown 保存，daily-log 每联系人一条。
- 点击同步后：采集内容进入“汇总 > 聊天”记录。
