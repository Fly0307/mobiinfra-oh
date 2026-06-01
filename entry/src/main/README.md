# entry/src/main 代码结构说明

本目录是 HarmonyOS 端应用、Native MNN 推理桥接、PC 端 Agent 脚本和 Prompt 模板的主目录。整体链路如下：

1. HarmonyOS App 在 `Index.ets` 中提供界面、模型下载、模型加载、本地/云端 Agent 启动入口。
2. App 内的 `AgentRouterServer.ets` 在手机侧监听 TCP 端口 `9126`，接收 PC 端 Python Agent 的请求。
3. 本地 MNN Agent 通过 `libentry.so` 调用 `napi_init.cpp` 中暴露的 Native 接口，复用 Prefix KV Cache 执行多步任务。
4. 云端 Agent 通过 `CloudModelClient.ets` 调用 OpenAI/Qwen 兼容接口，并把动作 JSON 返回给 PC 端执行。
5. PC 端 `harmony_agent.py` 负责轮询任务、截图、解析模型 JSON、通过 HDC/hmdriver2 执行动作。

## 顶层文件

| 文件 | 作用 |
| --- | --- |
| `module.json5` | HAP 模块配置，声明入口 Ability、页面列表、网络/后台运行/悬浮窗权限，以及备份扩展 Ability。 |

## ArkTS/ETS 应用代码

### `ets/entryability`

| 文件 | 作用 |
| --- | --- |
| `entryability/EntryAbility.ets` | App 主 Ability。负责应用生命周期、前后台切换、后台长时任务申请、悬浮窗创建/销毁，并注册 `AgentExecutionController` 的同步回调。 |

### `ets/entrybackupability`

| 文件 | 作用 |
| --- | --- |
| `entrybackupability/EntryBackupAbility.ets` | 备份/恢复扩展 Ability，目前仅记录 `onBackup` 和 `onRestore` 日志。 |

### `ets/autoagent`

| 文件 | 作用 |
| --- | --- |
| `autoagent/AutoAgentAbility.ets` | Accessibility 扩展 Ability。连接后把 Accessibility 上下文写入 `AppStorage`，为自动点击/滑动能力预留入口。 |

### `ets/components`

| 文件 | 作用 |
| --- | --- |
| `components/AppHeader.ets` | 通用页面头部组件，展示标题、副标题和隐私守护状态。 |

### `ets/pages`

| 文件 | 作用 |
| --- | --- |
| `pages/Index.ets` | 主页面。包含模型下载/删除/配置修改、模型加载、本地 Agent 启动、云端 Agent 配置与调试、日志入口、底部 Tab 容器等功能。 |
| `pages/FloatWindow.ets` | Agent 运行时悬浮窗页面。展示流式输出文本，并提供“终止”按钮触发 `AgentExecutionController.requestCancellation()`。 |
| `pages/LogView.ets` | 日志查看页面。支持查看 Native runtime 日志和云端 Agent 日志、自动刷新、复制和清空。 |
| `pages/OpTest.ets` | Native 算子/HiAI 精度与性能测试页面，用于调试 `opTest`、CPU/HiAI 模式、量化模式等。属于开发调试入口。 |
| `pages/home/HomePage.ets` | 首页展示页，展示数字分身、画像完整度、偏好标签和推荐卡片。 |
| `pages/collection/CollectionPage.ets` | 数据采集展示页，按聊天/购物/通知/娱乐模块展示模拟采集数据和偏好分布。 |
| `pages/task/TaskPage.ets` | 定时任务展示页，按场景展示任务卡片、状态和创建任务入口。 |

### `ets/utils`

| 文件 | 作用 |
| --- | --- |
| `utils/AgentExecutionController.ets` | Agent 执行状态控制器。集中维护是否运行、是否取消、悬浮窗同步回调、本地/云端取消回调、回到 App 回调。 |
| `utils/AgentRouterServer.ets` | 当前主要使用的手机端 TCP 路由服务器。监听 PC 端请求，并根据路由模式分发到本地 MNN Agent 或云端 Agent。处理 `poll`、`clear`、`agent_prefill`、`agent_step`、`agent_reset`、`action` 等协议。 |
| `utils/CloudModelClient.ets` | 云端模型客户端。负责构造 OpenAI/Qwen 兼容 Chat Completions 请求、管理请求取消、格式化调试 Prompt、调用 Planner/Decider。 |
| `utils/CloudDeciderPrompt.ets` | 云端 Qwen Decider 使用的 System/User/Step Prompt 常量。 |
| `utils/AccessibilityHelper.ts` | Accessibility 动态手势注入辅助封装。通过 `Reflect` 兼容部分系统 API 暴露差异。 |

## Native C++ 代码

| 文件/目录 | 作用 |
| --- | --- |
| `cpp/CMakeLists.txt` | Native `entry` 动态库构建配置，链接 NAPI、HiLog、rawfile、NNRT、CANN/HiAI 和 MNN 库。 |
| `cpp/napi_init.cpp` | 核心 Native NAPI 实现。暴露模型加载、普通对话、Agent Prefix/Step/Reset、Runtime 日志捕获、OMC/HiAI 算子测试、CPU/HiAI 精度测试等能力。 |
| `cpp/HIAIModelManager.h` | HiAI/NNRT 离线模型管理类声明，封装 OMC 模型加载、I/O Tensor 初始化、输入写入、推理和输出读取。 |
| `cpp/HIAIModelManager.cpp` | HiAI/NNRT 离线模型管理实现，选择 `HIAI_F` 设备、构建执行器、创建/释放 Tensor、执行同步推理。 |
| `cpp/types/libentry/Index.d.ts` | ArkTS 侧导入 `libentry.so` 时使用的 Native API 类型声明。 |
| `cpp/types/libentry/oh-package.json5` | Native 类型包描述文件。 |
| `cpp/include/MNN/**` | MNN SDK 头文件，属于第三方依赖，不建议业务开发中直接修改。 |
| `cpp/include/llm/**` | MNN LLM/VLM 相关头文件及 `httplib.h`，属于第三方/上游依赖，不建议业务开发中直接修改。 |

## PC 端 Python 脚本

| 文件 | 作用 |
| --- | --- |
| `python/harmony_agent.py` | HarmonyOS 端到端 Agent 主脚本。负责 HDC 端口转发、任务轮询、截图、Planner、Agent Prefill/Step 请求、JSON 恢复解析、动作执行、任务收尾和自愈。 |
| `python/hdc_server.py` | PC 端 HTTP 控制服务，默认监听 `9124`。App 可通过它执行 HDC 连接命令，并在检测到设备后自动拉起 `harmony_agent.py`。 |
| `python/serve_model.py` | PC 端模型文件 HTTP 服务，默认监听 `9123`，提供 `/api/files` 文件列表接口和静态文件下载。 |

## Prompt 模板

| 文件 | 作用 |
| --- | --- |
| `python/prompts/planner.md` | 通用 Planner Prompt，用于从用户任务中识别目标 App 等信息。 |
| `python/prompts/planner_fill.md` | Planner 补全/改写类模板。 |
| `python/prompts/planner_oneshot.md` | One-shot Planner 示例模板。 |
| `python/prompts/planner_oneshot_harmony.md` | HarmonyOS 应用场景的 One-shot Planner 模板。 |
| `python/prompts/change_task_description.md` | 任务描述改写模板。 |
| `python/prompts/auto_decider.md` | 自动决策模板。 |
| `python/prompts/decider.md` | 通用 Decider 模板。 |
| `python/prompts/decider_nohistory.md` | 不带历史的 Decider 模板。 |
| `python/prompts/decider_nohistory_v2.md` | 不带历史的新版 Decider 模板。 |
| `python/prompts/decider_v2.md` | 新版 Decider 模板。 |
| `python/prompts/decider_qwen3.md` | Qwen3 Decider 模板。 |
| `python/prompts/decider_qwen3_nohistory.md` | 不带历史的 Qwen3 Decider 模板。 |
| `python/prompts/e2e.md` | 端到端动作决策模板。 |
| `python/prompts/e2e_nohistory.md` | 不带历史的端到端动作决策模板。 |
| `python/prompts/e2e_qwen3.md` | Qwen3 端到端动作决策模板。 |
| `python/prompts/e2e_v2.md` | V2 端到端动作决策模板。 |
| `python/prompts/e2e_v2_old.md` | 旧版 V2 端到端模板，保留用于对照。 |
| `python/prompts/e2e_v2_agent_prefix.md` | Agent 模式 Prefix Prompt，定义动作空间、输出 JSON 格式、当前任务和约束。 |
| `python/prompts/e2e_v2_agent_variable.md` | Agent 模式每一步 Variable Prompt，填充历史和截图占位符。 |
| `python/prompts/e2e_v2_agent_prefix_noreason.md` | 无 reasoning 的 Agent Prefix Prompt。 |
| `python/prompts/e2e_v2_agent_variable_noreason.md` | 无 reasoning 的 Agent Variable Prompt。 |
| `python/prompts/e2e_v2_agent_prefixorigin.md` | 原始 Agent Prefix Prompt 备份。 |
| `python/prompts/e2e_v2_agent_variableorigin.md` | 原始 Agent Variable Prompt 备份。 |
| `python/prompts/e2e_v2_agent_prefixtest.md` | Agent Prefix 测试模板。 |
| `python/prompts/e2e_v2_agent_variabletest.md` | Agent Variable 测试模板。 |
| `python/prompts/grounder_bbox.md` | Grounder 框选坐标模板，输出 bbox。 |
| `python/prompts/grounder_coordinates.md` | Grounder 点坐标模板。 |
| `python/prompts/grounder_qwen3_bbox.md` | Qwen3 Grounder bbox 坐标模板。 |
| `python/prompts/grounder_qwen3_coordinates.md` | Qwen3 Grounder 点坐标模板。 |
| `python/prompts/annotation_en_general.md` | 英文通用动作标注说明模板。 |
| `python/prompts/annotation_zh_general.md` | 中文通用动作标注说明模板。 |

## 资源文件

| 文件/目录 | 作用 |
| --- | --- |
| `resources/base/element/string.json` | 字符串资源，包括模块描述、入口 Ability 描述和应用标签。 |
| `resources/base/element/color.json` | 浅色主题颜色资源，目前包含启动窗口背景色。 |
| `resources/base/element/float.json` | 浮点资源，目前包含页面文字大小示例值。 |
| `resources/dark/element/color.json` | 深色主题颜色资源。 |
| `resources/base/profile/main_pages.json` | 页面路由注册，包含 `Index`、`FloatWindow`、`OpTest`、`LogView`。 |
| `resources/base/profile/network_config.json` | 网络安全配置，允许 cleartext HTTP 流量，便于本地/内网调试。 |
| `resources/base/profile/backup_config.json` | 备份恢复配置。 |
| `resources/base/media/layered_image.json` | 应用图标 layered image 配置。 |
| `resources/base/media/background.png` | 应用图标/启动图背景图片。 |
| `resources/base/media/foreground.png` | 应用图标/启动图前景图片。 |
| `resources/base/media/startIcon.png` | 启动窗口图标。 |
| `resources/base/media/digital_avatar.png` | 首页数字分身展示图。 |
| `resources/base/media/rec_food.png` | 推荐卡片中的美食图片。 |
| `resources/base/media/rec_sport.png` | 推荐卡片中的运动图片。 |
| `resources/base/media/rec_travel.png` | 推荐卡片中的出行图片。 |

## 通信协议约定

PC 与手机 App TCP 服务之间使用简单文本协议：

- 请求体：JSON 字符串 + `<<EOF>>`
- 响应体：JSON 或模型原始文本 + `<<EOF>>`
- 常用请求类型：
  - `poll`：PC 轮询当前任务。
  - `clear`：清理当前任务和模型上下文。
  - `error`：PC 上报任务执行错误。
  - `agent_prefill`：本地 Agent 预填 Prefix Prompt，建立 KV Cache。
  - `agent_step`：发送每一步变量 Prompt 和截图。
  - `agent_reset`：重置 Agent 上下文。
  - `action`：一次性文本/图文推理请求。
  - `cloud_history_append`：云端 Agent 在 PC 执行动作成功后追加历史。

## 维护建议

1. 优先维护 `AgentRouterServer.ets`。当前主流程统一通过它承接手机侧 TCP 请求分发和本地/云端 Agent 路由。
2. 默认服务器地址已集中为 `Index.ets` 顶部常量，修改部署地址时优先改常量，不要在 UI 逻辑中散落硬编码。
3. `python/harmony_agent.py` 是 HarmonyOS 任务执行主入口；调整 Prompt、动作协议或设备控制逻辑时应优先验证它的主链路。
4. `cpp/include/**` 是第三方依赖目录，业务修改应集中在 `napi_init.cpp`、`HIAIModelManager.*` 和 ArkTS/Python 调用层。
5. Prompt 文件会直接影响模型输出 JSON 格式，修改后应同步验证 `extract_json_payload()` 和动作执行链路。
6. 运行中产生的截图、日志、`__pycache__`、模型文件和调试输出不应提交到源码仓库。