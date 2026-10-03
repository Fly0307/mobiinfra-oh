# 聊天页数字人 2.5D 动效设计

## 背景

当前聊天页已经通过 `avatarForegroundUri` 使用数字分身透明 PNG，但数字人只在空聊天欢迎态静态显示。
进入正式聊天后，助手消息头像仍是 34x34 的文字徽标，数字人没有持续存在感。

本设计目标是把聊天中的助手头像升级为轻量的 2.5D 数字人头像，使用户在对话中能感知到“数字人正在回应或思考”，同时保持消息阅读稳定，不引入真 3D 模型和语音链路。

## 已确认决策

- 主视觉方向：2.5D 分层视差。
- 常驻位置：替代助手普通聊天消息头像。
- 第一版动效范围：点击反馈 + 思考态呼吸和光圈脉冲。
- 暂不实现：语音交互、回复态口型动画、glTF/Component3D 真 3D、帧动画资源生成。

## 现状约束

- `ChatPage` 接收 `avatarForegroundUri`，来源是 `Index.homeProfile.avatarForegroundUri`。
- `ChatMessageList.Avatar()` 当前统一渲染文字徽标，用于用户、助手、上下文、任务结果、任务过程等多种消息。
- `ChatMessageList` 的底部 `thinking` 行当前用文字徽标和“处理中...”提示表示生成中。
- 数字分身透明 PNG 由头像前景缓存生成，失败时可能为空，因此必须保留文字徽标兜底。

## 体验目标

第一版只做低风险但明显可感知的互动：

1. 助手普通聊天消息显示 2.5D 数字人头像。
2. 用户点击数字人头像时，头像轻弹或点头一次，阴影同步压缩后恢复。
3. 助手正在生成回复时，底部“处理中...”行的数字人进入思考态：人物轻微呼吸，背景光圈脉冲。
4. 任务过程、任务结果、上下文压缩提示等功能型消息继续使用原文字徽标，避免语义混乱。
5. 没有可用 `avatarForegroundUri` 时，完全回退当前文字徽标，不影响聊天功能。

## 组件设计

新增 `entry/src/main/ets/pages/chat/DigitalAvatarTypes.ets`：

```ts
export type DigitalAvatarVisualState = 'idle' | 'thinking';
export type DigitalAvatarSize = 'message';
```

新增 `entry/src/main/ets/pages/chat/DigitalAvatarView.ets`：

- 输入 `avatarForegroundUri`、`fallbackText`、`visualState`、`size`。
- 内部使用 `Stack` 分层：
  - 背景光圈层：思考态时做 opacity 和 scale 脉冲。
  - 地面阴影层：点击反馈和思考态同步改变 scale 和 opacity。
  - 人物 PNG 层：渲染透明前景图。
  - 高光层：低透明度渐变或简洁光泽，用于增强 2.5D 立体感。
- 当 `avatarForegroundUri` 为空时，渲染原文字徽标样式。
- 点击时只更新组件内部动画状态，不触发消息折叠或业务动作。

## 消息列表接入

`ChatMessageList` 新增属性：

```ts
@Prop avatarForegroundUri: string = '';
```

`ChatPage.ConversationPanel()` 向 `ChatMessageList` 传入 `avatarForegroundUri`。

`ChatMessageList.Avatar(message)` 调整规则：

- `message.role === 'assistant' && message.kind === 'chat'`：使用 `DigitalAvatarView`。
- `message.role === 'user'`：继续显示“我”。
- `task_trace`、`task_result`、`context_notice`：继续显示“任”“压”等功能徽标。
- 其他系统消息：保持当前徽标。

底部 `thinking` 行调整：

- 左侧头像使用 `DigitalAvatarView({ visualState: 'thinking' })`。
- 右侧仍显示“处理中...”，保持现有布局和滚动逻辑。

## 动效规范

动画只作用于 transform 和 opacity，避免消息列表重排：

- 点击反馈：
  - 人物层 `translateY` 上移后回落，配合轻微 `scale`。
  - 阴影层先缩小变淡，再恢复。
  - 持续时间约 360ms 到 520ms。
- 思考态：
  - 人物层慢速 `scale` 呼吸。
  - 光圈层循环 `scale` 与 `opacity` 脉冲。
  - 阴影层轻微同步变化。
  - 持续时间约 1400ms 到 1800ms，循环播放。

不动画 `width`、`height`、`margin`、`padding` 等布局属性。

## 错误和降级

- 前景图为空：回退文字徽标。
- 图片加载失败：保留组件尺寸，显示文字徽标。
- 思考态结束：恢复 `idle`。
- 会话切换、消息重建：动画状态只在组件内部短暂存在，不写入会话存储。

## 验证计划

- `git diff --check`。
- Hvigor 单元测试，优先用项目约定的 Hvigor test 命令；如沙箱卡住，记录到达阶段和错误。
- 手工检查 1080x2340 预览：
  - 空聊天欢迎态仍显示大数字人。
  - 有消息后，助手普通消息头像变为 2.5D 数字人。
  - 用户、任务、上下文消息头像不变。
  - 点击助手数字人头像有反馈。
  - 云端或本地生成中底部 thinking 行有呼吸和光圈脉冲。
  - 长消息、图片预览、会话抽屉不被头像遮挡。

## 后续扩展

- 回复态：流式回复时增加轻微说话节奏。
- 语音态：录音和 TTS 接入后增加 listening、speaking 状态。
- 拖动视差：后续可根据触摸位置添加轻微倾斜和阴影偏移。
- 资源化参数：将尺寸、颜色、动效时长抽成常量，便于统一调优。
