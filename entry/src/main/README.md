# entry/src/main 架构说明

本目录包含 HarmonyOS App、Native MNN 推理桥、PC 侧 HDC bridge、workflow 编排和 Agent prompt 相关代码。

当前主架构是：Agent loop 尽量在手机 App 内执行，PC 端只负责 HDC 设备控制、截图和少量控制层准备。旧版 PC 轮询 `9126` 的链路仍保留用于兼容和调试，但本地 MNN Agent、云端 Agent、workflow 的主路径不再依赖 PC 发起整个 loop。

## 主链路

1. HarmonyOS App 在 `pages/Index.ets` 提供 UI、模型加载、云端配置、workflow 入口和 HDC bridge 配置。
2. 本地 MNN Agent 和云端 Agent 由 `utils/AgentLoopRunner.ets` 在 App 内执行完整 loop：拼装 prompt、调用 Planner/Decider、解析 JSON、维护 history、控制暂停/取消和确认弹窗。
3. workflow 由 `utils/WorkflowRunner.ets` 在 App 内执行编排、Planner、Decider、工具步骤、run summary、daily-log 和输出文件写入。
4. PC 端 `python/hdc_server.py` 暴露 `POST /api/workflow`，作为 HDC bridge 执行截图、启动 App、点击、输入、滑动、按键、等待、设备控制准备等操作。
5. `python/harmony_agent.py` 中的旧版 PC Agent loop、截图和动作实现仍作为 HDC bridge 的底层能力与兼容路径保留。

## Agent loop 分工

### 本地 MNN Agent

- 入口：`Index.ets` 本地 Agent 按钮。
- Loop：`AgentLoopRunner.runLocalTask()`。
- 模型调用：`libentry.so` 的 `chat`、`agentPrefill`、`agentStep`、`agentReset`。
- Planner prompt：`planner_oneshot_harmony.md`，找不到时回退 `planner.md`。
- Decider prompt：`e2e_v2_agent_prefix.md` / `e2e_v2_agent_variable.md`；当 PC HDC server 以 `--no_reason` 启动时使用 `_noreason` 版本。
- 截图：App 先隐藏悬浮窗，再请求 PC HDC bridge 截图；本地 MNN 使用 `factor=0.25`，并按旧逻辑把 `<img>...<hw>h,w</hw></img>` 注入 prompt。
- JSON 解析：App 内 `AgentActionParser.ets` 解析模型输出，并把 0-1000 归一化坐标转换为真实屏幕坐标。
- 动作执行：App 把已解析的 HDC action payload 发送给 PC `/api/workflow` 的 `gui_action`。

### 云端 Agent

- 入口：`Index.ets` 云端 Agent 按钮、首页推荐任务。
- Loop：`AgentLoopRunner.runCloudTask()`。
- Planner：`CloudModelClient.chatPlanner()`，使用 Planner 服务地址。
- Decider：`CloudModelClient.chatQwenDecider()`，使用 `CloudDeciderPrompt.ets` 中的 Qwen system/user/current-step prompt。
- 云端 Agent 的 prefix prompt 只用于保持和旧逻辑一致的 task 提取与 no-reason 配置；真正的 Decider 输入仍由 `CloudDeciderPrompt.ets` 组织，和 workflow 的 Qwen Decider 组织方式保持一致。
- 截图：云端 Agent 使用 `factor=0.5`，PC 仅截图，不再反向连接 `9126` 控制悬浮窗。
- history：App 在 HDC 动作执行成功后追加规范化后的模型 JSON 字符串，保持旧 `cloud_history_append` 的语义。

### Workflow

- 入口：`TaskPage.ets` 触发 `Index.runWorkflowTask()`。
- Loop：`WorkflowRunner.ets`。
- Planner prompt：`planner_oneshot_harmony.md`，由 App 侧 `AgentPromptTemplates.ets` 读取，不再向 PC 拉取模板。
- Decider prompt：`CloudModelClient.chatQwenDecider()`，不要和 MNN/cloud Agent 的 `e2e_v2_agent_*` prompt 混用。
- JSON 解析：`WorkflowRunner` 使用 `AgentActionParser` 在 App 内解析 Decider 输出，再发送结构化 HDC payload 给 PC。
- 输出结构：workflow 的 run summary、daily-log、截图、工具输出等仍写在 App `filesDir/workflows` 下，保持现有输出字段和文件结构；不再创建空的 `steps/1/2/3` 目录。

## Prompt 模板

Python prompt 源文件仍位于：

```text
python/prompts/
```

App 主路径使用 `utils/AgentPromptTemplates.ets` 中的模板镜像，目的是让 prompt 装配在 App 内完成，同时保证模型输入和原 Python prompt 完全一致。更新 prompt 时要同步：

- `planner_oneshot_harmony.md`
- `planner.md`
- `e2e_v2_agent_prefix.md`
- `e2e_v2_agent_prefix_noreason.md`
- `e2e_v2_agent_variable.md`
- `e2e_v2_agent_variable_noreason.md`
- `e2e_v2.md`

注意：MNN/cloud Agent 的 `e2e_v2_agent_*` prompt、workflow 的 Planner prompt、Qwen Decider 的 `CloudDeciderPrompt.ets` 是不同输入，不要合并成一套。

## PC HDC Server

常用启动：

```bash
python entry/src/main/python/hdc_server.py
python entry/src/main/python/hdc_server.py --no_reason
python entry/src/main/python/hdc_server.py --workflow_only
```

`hdc_server.py` 默认监听 `9124`。主接口是 `POST /api/workflow`，常用 action：

- `health`：检查 HDC/tunnel 状态。
- `agent_config`：返回 `no_reason` 和 step 配置。
- `prepare_agent_run`：重置 hmdriver2/HDC 控制层状态。
- `screenshot`：只做 HDC 截图和 resize；悬浮窗隐藏/恢复由 App 负责。
- `app_start`：启动目标 App。
- `gui_action`：执行 App 已解析好的 click、click_input、input、swipe、keyevent、sleep、app_start 等动作。
- `execute_decider_action`、`load_prompt_template`：旧兼容接口，新主路径不依赖它们。

## 9126 兼容链路

`utils/AgentRouterServer.ets` 仍可在 App 内监听 `9126`，处理旧 PC `harmony_agent.run_agent_loop()` 的 `poll`、`agent_prefill`、`agent_step`、`action` 等请求。这个链路现在是兼容和调试用途：

- 旧 PC loop 仍可轮询 App 任务并执行。
- 新 MNN/cloud Agent 主路径不再调用 `submitLocalTask()` / `submitCloudTask()` 等待 PC 轮询。
- `capture_overlay_hide` / `capture_overlay_restore` 仍为旧截图函数保留；新 `/api/workflow` 截图不再反连 `9126`。

## 关键文件

| 文件 | 作用 |
| --- | --- |
| `ets/pages/Index.ets` | UI 入口、模型加载、HDC 配置、Agent/workflow 启动和确认弹窗。 |
| `ets/utils/AgentLoopRunner.ets` | App 内 MNN/cloud Agent loop。 |
| `ets/utils/AgentActionParser.ets` | 模型 JSON 提取、动作解析、坐标还原、HDC payload 生成。 |
| `ets/utils/AgentPromptTemplates.ets` | App 侧 prompt 模板镜像。 |
| `ets/utils/HdcWorkflowBridge.ets` | App 到 PC `/api/workflow` 的 HTTP bridge。 |
| `ets/utils/WorkflowRunner.ets` | App 内 workflow 编排和输出文件写入。 |
| `ets/utils/CloudModelClient.ets` | OpenAI-compatible Planner/Decider 请求。 |
| `ets/utils/CloudDeciderPrompt.ets` | Qwen Decider 专用 prompt。 |
| `ets/utils/AgentRouterServer.ets` | 旧 9126 TCP Agent router 兼容层。 |
| `cpp/napi_init.cpp` | Native MNN/NAPI 实现。 |
| `python/hdc_server.py` | PC HDC bridge HTTP 服务。 |
| `python/harmony_agent.py` | 旧 PC Agent loop 和 HDC/hmdriver2 底层能力。 |

## 验证建议

- Python 改动：运行 `python -m py_compile entry/src/main/python/hdc_server.py entry/src/main/python/harmony_agent.py`。
- ArkTS 改动：优先用 DevEco/Hvigor 构建 entry 模块。
- HDC 可达性：运行 `hdc list targets`，并在 App 内触发 HDC Server 检查。
- Agent 行为：分别验证本地 MNN Agent、云端 Agent、workflow 中至少一个需要点击/输入/滑动的任务，确认截图、prompt、history、动作执行和输出文件都正常。
