# 聊天页会话管理设计

## 背景

当前“聊天”页只有单一输入和单一输出状态：云端智能体使用 `cloudOutput` 作为日志式文本，本地推理使用 `chatHistory` 字符串展示对话。用户输入后可以发送普通聊天或下发任务，但页面没有历史会话列表、会话文件持久化、会话删除联动文件删除，也没有结构化区分用户消息、助手回复和任务执行过程。

本设计在现有聊天页基础上补齐会话管理能力，同时保持 `Index.ets` 中本地模型、云端客户端、AgentRouter 和 HDC 链路不被重写。

## 用户确认的产品方向

- 历史会话同时支持“云端智能体”和“本地推理”两种模式。
- 点击聊天页左上角菜单展开左侧抽屉，查看历史会话和新建会话。
- 切换会话时恢复该会话内的历史聊天记录。
- 同一个会话内要保存上下文，后续发送继续使用该会话上下文。
- 删除会话时同时删除会话对应的文件。
- 消息展示区域要正确区分用户发送消息和助手回复。
- 下发类任务的最终结果可以直接展示；中间执行过程默认折叠，可手动展开查看。

## 范围

本设计覆盖聊天页会话列表、会话持久化、消息展示、上下文恢复、会话删除和任务过程折叠。它不改变：

- PC 侧 HDC 服务和 9126 `<<EOF>>` TCP 协议。
- 云端 `/v1/chat/completions` URL 拼接规范。
- NAPI/C++ 本地模型生命周期和 Agent 推理 API。
- Workflow 文件管理、daily-log 和运行文件存储模型。
- `pages/LogView` 作为 Native/Cloud runtime log 页面的职责。

## 布局方案

采用用户确认的 A 方案：左上角菜单打开抽屉式会话列表。

聊天页默认保持当前单栏消息体验。点击左上角 `☰` 后显示左侧抽屉：

- 顶部显示“会话”和“新建会话”按钮。
- 会话行显示标题、模式、更新时间和最后一条消息摘要。
- 当前会话高亮。
- 每行提供删除入口；删除前弹窗确认。
- 关闭抽屉后回到当前会话消息列表。

不采用常驻分栏，因为 1080 x 2340 手机预览中常驻列表会持续压缩消息区，用户消息和任务结果卡片更容易截断。

## 数据模型

新增 `entry/src/main/ets/pages/chat/ChatSessionTypes.ets`，定义会话和消息结构。

会话索引只保存列表展示所需字段：

```ts
export interface ChatSessionSummary {
  id: string;
  title: string;
  mode: string;
  fileName: string;
  createdAt: number;
  updatedAt: number;
  messageCount: number;
  lastMessagePreview: string;
}
```

会话文件保存完整消息和模式状态：

```ts
export interface ChatSessionRecord {
  id: string;
  title: string;
  mode: string;
  createdAt: number;
  updatedAt: number;
  messages: ChatMessage[];
}
```

消息使用结构化模型，避免继续把整段日志拼成一个字符串：

```ts
export interface ChatMessage {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'task';
  kind: 'chat' | 'task_result' | 'task_trace';
  content: string;
  trace: string[];
  collapsed: boolean;
  createdAt: number;
}
```

约定：

- `user/chat`：用户普通消息或任务目标。
- `assistant/chat`：云端 Planner 或本地模型回复。
- `task/task_result`：下发任务的最终用户可读结果。
- `task/task_trace`：执行过程、轮询日志、Planner/Decider 中间状态，默认 `collapsed = true`。

## 存储设计

新增 `entry/src/main/ets/utils/ChatSessionStorage.ets`，使用 app sandbox `filesDir` 下的 JSON 文件：

```text
chat-sessions/
  session-index.json
  sessions/
    <session-id>.json
```

`session-index.json` 保存 `ChatSessionSummary[]`。每个会话一个 `<session-id>.json`，删除会话时删除对应 JSON 文件。

存储 API 以纯静态方法为主，和 `WorkflowStorage.ets` 风格一致：

- `ensureWorkspace(filesDir)`
- `loadIndex(filesDir)`
- `createSession(filesDir, mode)`
- `loadSession(filesDir, id)`
- `saveSession(filesDir, session)`
- `appendMessage(filesDir, sessionId, message)`
- `renameFromFirstUserMessage(filesDir, sessionId)`
- `deleteSession(filesDir, id)`
- `nextSessionAfterDelete(filesDir, deletedId)`

删除逻辑：

1. 从索引中移除目标会话。
2. 删除该会话 JSON 文件。
3. 如果删除的是当前会话，切换到最近更新的会话。
4. 如果没有剩余会话，为当前模式创建一个新会话。

## 上下文策略

### 云端智能体

云端普通对话改为使用会话消息数组构造 OpenAI-compatible `messages`：

- 历史 `user/chat` 转为 `{ role: 'user', content }`。
- 历史 `assistant/chat` 转为 `{ role: 'assistant', content }`。
- `task_trace` 默认不放入普通聊天上下文，避免把大量执行日志反复塞回模型。
- 当前用户消息追加后再请求云端，成功后追加助手回复。

在 `CloudModelClient.ets` 中新增面向普通聊天的 `chatPlannerMessages(messages, config)`，复用已有 `chatCompletionText`/`chatMessages` 逻辑，不改变 Decider 和 Workflow 调用。

### 本地推理

本地 NAPI 侧只有一个全局 `g_messages` 上下文。切换本地会话时要恢复两层状态：

- UI 层：从会话 JSON 加载消息列表并渲染。
- 模型层：调用 `mnnllm.reset()` 清空当前原生上下文，再按历史用户轮次重放必要上下文。

本地重放策略采用保守实现：

- 若切换到本地会话且模型已加载，调用 `mnnllm.reset()`。
- 依次读取该会话历史中的 `user/chat` 消息，调用 `mnnllm.chat(userMessage)` 重建原生上下文。
- 重放期间不改写会话文件、不新增消息、不更新 UI 文本。
- 如果重放失败，UI 仍显示历史消息，但下一轮发送前给出“本地上下文恢复失败，将从当前消息继续”的状态提示。

这个策略避免改动 C++ `g_messages` 导入/导出接口，代价是切换长会话时会有额外模型推理耗时。后续如需优化，可单独增加 NAPI 上下文导入接口。

## 消息展示

`ChatPage.ets` 从日志文本展示改为消息列表展示：

- 用户消息右侧深色气泡。
- 助手消息左侧浅色气泡。
- 系统状态使用居中小字或浅色提示。
- 任务结果使用卡片，标题为“任务结果”。
- 任务过程使用折叠卡片，标题为“执行过程”，默认只显示摘要和“展开”按钮。

长文本仍使用纵向滚动，消息气泡设置 `maxLines` 或自然换行，避免固定宽度导致窄屏截断。

## 任务执行过程折叠

下发任务会产生两类信息：

- 最终结果：直接展示为 `task_result`。
- 中间过程：追加到 `task_trace.trace` 数组，默认折叠。

云端日志 `appendCloudLog` 仍写入 AppLogger 和 runtime log，供 `LogView` 查看完整日志。聊天区只展示和当前会话相关的过程摘要，不把所有 runtime log 直接铺进对话框。

折叠状态保存在会话文件中，用户展开/收起后持久化，切换会话后保持上次状态。

## `Index.ets` 职责调整

`Index.ets` 继续负责：

- 初始化 `filesDir`、模型目录、AgentRouter、CloudModelClient。
- 执行云端 Planner、本地 chat、云端/本地任务下发。
- HDC、Workflow、截图和 runtime log 相关业务方法。

新增状态：

- `chatSessions: ChatSessionSummary[]`
- `activeChatSessionId: string`
- `activeChatMessages: ChatMessage[]`
- `chatSessionDrawerOpen: boolean`
- `restoringLocalSession: boolean`

新增回调传给 `ChatPage`：

- `onOpenSessionDrawer`
- `onCloseSessionDrawer`
- `onCreateChatSession(mode)`
- `onSelectChatSession(id)`
- `onDeleteChatSession(id)`
- `onToggleTaskTrace(messageId)`

`ChatPage` 仍作为展示组件，不直接访问文件系统、模型或 HDC。

## 错误处理

- 会话索引损坏：备份为 `.broken.<timestamp>`，重建一个默认会话。
- 会话文件缺失：从索引移除该会话并切到最近会话。
- 删除文件失败：保留索引项并显示 toast，避免 UI 显示已删但文件仍存在。
- 当前会话删除：立即切换到最近会话或新建会话。
- 本地上下文重放失败：保留 UI 历史，追加系统提示，不阻断后续普通发送。
- 忙碌中切换会话：禁止切换或提示“当前任务处理中”，避免把回复写入错误会话。

## 测试与验证

新增纯逻辑单测覆盖 `ChatSessionStorage` 和消息摘要 helper：

- 创建默认会话并生成索引。
- 追加用户/助手消息后更新 `updatedAt`、`messageCount` 和摘要。
- 删除会话时删除对应 JSON 文件。
- 删除当前会话后选择最近会话。
- 任务 trace 默认折叠，toggle 后状态持久化。
- 云端上下文构造不包含 `task_trace` 明细。

Codex 侧不运行已知会阻塞的 Hvigor test 命令：

```bash
env DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test --mode module -p module=entry@default -p product=default --no-daemon
```

实现后 Codex 至少执行：

- `git diff --check`
- 相关文件静态检查和导入检查

Hvigor test 由用户在本机手动执行。

## 非目标

- 不实现跨设备同步会话。
- 不做会话搜索。
- 不做会话导出。
- 不重写 PC 侧 Agent 协议。
- 不把完整 runtime log 默认塞进聊天消息区。
- 不新增 C++ NAPI 的会话导入/导出接口。
