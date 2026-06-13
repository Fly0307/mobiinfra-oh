# 聊天入口与设置中心重构设计

## 背景

当前底部 tab 中的“助手”和“云端”承载了大量配置能力，包括本地推理、云端 Planner/Decider、HDC、模型下载、运行参数和数字分身图片服务。`Index.ets` 同时承担底部导航、聊天交互、云端任务、本地推理、HDC 和多组设置表单，页面职责过重，后续扩展配置项时容易继续堆叠。

本次重构目标是把用户高频入口和配置入口分离：聊天与任务下发集中到中心 tab，配置集中到独立设置 tab，并将对应页面拆成独立文件，避免继续扩大 `Index.ets`。

## 用户确认的产品方向

- 底部 tab 改为：`首页 / 汇总 / 聊天 / 任务 / 设置`。
- 原“采集”tab 的显示名称改为“汇总”，保留现有 Collection 页面职责。
- 新增 `pages/chat/ChatPage.ets`，作为底部中心 tab 的主要聊天入口。
- 新增 `pages/settings/SettingsCenterPage.ets`，作为统一配置中心。
- 默认聊天模式为“云端智能体”。
- 聊天页参考千问 App 主页：轻量顶部标题与模式入口，中间空态欢迎区和推荐任务，底部固定输入框。
- 输入后提供两类核心动作：普通对话/规划、下发任务。
- 本地推理保留为模式切换或更多面板能力，不再作为主配置页展示。

## 范围

本设计覆盖 ArkTS 页面结构、底部导航、聊天入口、设置中心分区、状态和回调拆分。它不改变 PC 侧 HDC 服务、`<<EOF>>` TCP 协议、云端 `/v1/chat/completions` URL 拼接规则、NAPI 本地模型生命周期或 Workflow 存储模型。

## 架构

`Index.ets` 保留为应用 shell，负责：

- 初始化 `PersistentStorage` 默认值。
- 持有跨 tab 状态和现有业务方法。
- 渲染底部 tab 容器。
- 将状态、事件和业务回调传入新页面组件。

新增页面组件：

- `entry/src/main/ets/pages/chat/ChatPage.ets`
  - 专注聊天 UI、输入框、模式选择、推荐任务、日志/截图摘要和发送动作。
  - 不直接实现云端 Planner、AgentRouter、本地模型加载或 HDC 细节。
  - 通过显式 props/callback 调用 `Index.ets` 中已有方法。
- `entry/src/main/ets/pages/settings/SettingsCenterPage.ets`
  - 专注配置中心分区和表单 UI。
  - 通过 `@StorageLink` 或显式传入的绑定状态复用现有 `PersistentStorage` key。
  - 通过 callbacks 调用模型下载、HDC 连接测试、运行日志跳转等现有能力。

`Index.ets` 在本次重构后不再包含大段“助手页”和“云端页”布局代码。旧逻辑按照页面职责拆入 `ChatPage` 和 `SettingsCenterPage`，业务方法先保留在 `Index.ets`，避免一次性重写 Agent/HDC/模型链路。

## 底部导航设计

tab 顺序固定为：

1. 首页：现有 `HomePage`。
2. 汇总：现有 `CollectionPage`，仅改 tab 文案。
3. 聊天：新增 `ChatPage`，中心突出。
4. 任务：现有 `TaskPage`。
5. 设置：新增 `SettingsCenterPage`。

旧 `CloudAssistantPage` 和 `AssistantPage` 不再作为底部 tab 暴露。首页推荐任务原先跳转到“云端”tab 的逻辑改为跳转到“聊天”tab，并尽量保留任务文本上下文。

## ChatPage 设计

聊天页以“云端智能体”为默认模式，页面结构分为三块：

- 顶部栏：左侧可预留菜单/历史入口，中间显示应用或智能体名称，旁边提供模式入口；右侧预留静音/状态/日志入口。
- 主内容：空态欢迎语、数字分身或智能体头像、推荐任务 chip。推荐任务偏向本项目实际能力，例如设备操作、截图整理、Workflow 生成、任务规划。
- 底部输入区：固定在底部，包含文本输入、附件/截图入口、发送/执行入口。输入后支持“发送给 Planner”和“下发任务”两类动作。

模式设计：

- 云端智能体：默认模式。普通发送调用云端 Planner/对话规划能力；下发任务调用现有云端 Agent 任务执行链路。
- 本地推理：作为模式切换项或更多面板项。普通发送调用 `mnnllm.chat`；本地 Agent 执行能力保留，但相关配置不在聊天主界面展开。

聊天页只展示运行状态摘要，例如“Planner 思考中”“Agent 执行中”“HDC 未连接”。详细服务地址、API Key、模型文件和运行参数移入设置中心。

## SettingsCenterPage 设计

设置中心使用可扩展分区结构。每个分区由标题、说明、设置项列表和可选操作区组成，后续新增配置只需要增加一个分区或设置项 Builder。

一级分区如下：

1. 个人与隐私
   - 隐私守护状态。
   - 云端/本地自动确认开关。
   - 数字分身图片服务配置入口，包括图片服务地址、API Key、模型和尺寸。

2. 数据采集
   - 图库采集设置入口。
   - OCR 开关、OCR 关键词过滤、图片缩放。
   - 模型识别并发、Embedding 并发、Embedding 服务地址/API Key/模型。
   - AMap Web Key。

3. 模型与智能体
   - 云端 Planner 服务地址。
   - 云端 Decider 服务地址、API Key、Decider Model。
   - 本地模型下载服务地址。
   - 本地模型文件检查、下载、删除。
   - 本地运行参数，例如线程数和 Config 查看/修改。
   - HDC Server、无线 HDC 目标、自动连接、手动配对、连接测试。

4. 任务与自动化
   - Agent 执行相关开关。
   - Workflow 文件管理入口仍指向现有 `WorkflowFileViewer`。
   - Runtime Logs 入口。
   - 与真实设备副作用相关的确认策略入口。

5. 存储与关于
   - 模型文件占用和清理动作。
   - 截图、调试产物和运行日志清理入口。
   - Op Precision Test、Runtime Logs 等调试入口。
   - 应用版本、端口说明和本机服务依赖说明。

设置中心不把 Workflow 文件预览重新搬回主 tab；`TaskPage` 继续负责任务列表和运行入口，`WorkflowFileViewer` 继续负责配置、daily-log 和运行文件查看。

## 状态与数据流

现有 `PersistentStorage` key 保持不变，避免破坏用户已保存配置。默认值仍来自 `DefaultEndpointConfig.ets`。

`Index.ets` 将向 `ChatPage` 传入：

- 当前聊天模式。
- 云端输出、云端输入、云端截图、云端执行状态。
- 本地输出、本地输入、本地聊天历史、本地模型加载状态。
- 发送 Planner、下发云端任务、本地 chat、本地 Agent 执行、启动后端、清理截图等回调。

`Index.ets` 将向 `SettingsCenterPage` 传入：

- 服务地址、模型配置、HDC 配置、图片服务配置、自动确认开关等状态。
- 配置更新、模型下载/删除/检查、HDC 自动连接/手动配对/测试、跳转日志/测试页面等回调。

图库采集设置已经存在于 `GalleryPage.ets`。实现时优先复用相同 `PersistentStorage` key，将配置集中展示到设置中心；如局部能力仍依赖图库页内部状态，则设置中心提供跳转入口并逐步迁移。

## 错误处理与反馈

聊天页只显示高层状态和最近错误，避免把服务地址和配置细节暴露为主界面内容。典型状态包括：

- 云端 Planner 请求失败。
- HDC Server 不可达。
- 本地模型未加载。
- Agent 执行中或等待确认。

设置中心显示可操作错误和修复入口，例如连接测试失败、HDC 自动发现失败、模型文件缺失、API Key 为空。涉及真实设备操作的自动确认默认不扩大授权，仍由用户显式开启。

## 测试与验证

实现计划阶段应优先把可测试逻辑抽成小单元，例如 tab 配置、设置分区定义、模式枚举和跳转目标。验证重点：

- 底部 tab 顺序和文案正确：`首页 / 汇总 / 聊天 / 任务 / 设置`。
- 首页推荐任务跳转到聊天 tab。
- 聊天页默认云端智能体模式，普通发送和下发任务调用不同回调。
- 本地推理模式仍可发送 `mnnllm.chat`。
- 设置中心能编辑原助手/云端页已有配置，且存储 key 不变。
- HDC、模型下载、日志、OpTest、Workflow 文件管理入口仍可达。

最终实现后至少执行：

- `git diff --check`
- 不依赖真机的 Hvigor 测试或构建命令；若 Codex 沙箱卡住或受限，记录失败阶段并要求在 DevEco/真实终端补跑。

## 非目标

- 不重写云端 Planner/Decider 协议。
- 不改变 PC 侧 Python Agent 和 HDC 命令协议。
- 不删除本地推理能力。
- 不把 Workflow 文件查看重新塞回 `TaskPage` 或 `Index.ets`。
- 不迁移或重命名现有持久化 key。
