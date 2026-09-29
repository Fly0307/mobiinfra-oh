# 小艺 A2A 双向接入调研与版本兼容方案

更新日期：2026-09-29。本文基于华为公开文档和当前仓库源码做静态调研，尚未接入小艺开放平台，也未在设备上验证。

## 目标与结论

目标有两个方向，接入方式不同：

| 方向 | 官方开放路径 | 对本项目的意义 |
| --- | --- | --- |
| 小艺调用本应用 | 小艺开放平台的**端 A2A Agent**，应用提供 `AgentExtensionAbility`、AgentCard 和消息处理；若能力已部署在服务器，可选云 A2A | 优先用端 A2A 读取手机沙箱中的个人记忆。云 A2A 无法天然访问本机记忆，需要另建授权同步链路。 |
| 本应用调用小艺 | Agent Framework Kit 的 `FunctionComponent` 可在应用内拉起指定智能体，并可配置 `agentId`、`queryText` | 适合让用户进入小艺对话。已核查的公开接口尚不足以确认第三方 App 能在后台调用通用小艺并取得机器可读结果。此需求应向华为确认开放范围。 |

端 A2A 和云 A2A 是华为列出的不同接入模式。[华为 Harmony Intelligence 概览](https://developer.huawei.com/consumer/cn/harmonyos-ai)；[端 A2A 平台配置步骤](https://developer.huawei.com/consumer/cn/doc/service/device-a2a-0000002640106106)；[Agent Framework Kit 接口变更说明](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/js-apidiff-agentframeworkkit-6003)。

## 当前项目可复用的部分

- `entry/src/main/ets/datamanager/DataManagerQueryEventsTool.ets`：已有 `query_events` 检索工具，可作为个人记忆查询的业务入口。
- `entry/src/main/ets/utils/ChatToolRegistry.ets`：已有聊天工具定义与执行封装，但其 OpenAI 工具调用格式不是小艺 A2A 报文，需新增协议适配层。
- `entry/src/main/ets/pages/Index.ets`：注册了 `query_events` 与手机 GUI 任务工具；GUI 操作已有用户确认流程。A2A 入口不应绕过现有授权与确认。
- `entry/src/main/ets/utils/CloudModelClient.ets`：现有云模型客户端使用聊天模型接口，不能仅替换 URL 就用于小艺 A2A。
- `entry/src/main/module.json5`：目前未注册 Agent Extension。

## 推荐接入流程

1. **限定首批技能。**先开放“查询某段时间的个人记录”和“总结上周记录”等只读能力。返回必要摘要和来源，不默认返回身份证号、家庭住址等高敏感字段。写入、分享和手机 GUI 操作要另行授权并保留逐次确认。
2. **实现端 A2A 入口。**注册 Agent Extension、配置 AgentCard，并增加独立的消息适配层。该层校验请求、身份和技能范围，将请求转换为内部业务调用，再按平台协议返回状态和结果。API 24 的 `AgentExtensionAbility` 提供 `onData`、`onAuth` 等回调，`AgentHostProxy` 提供 `sendData` 与 `authorize`；新版本 Agent Framework Kit 还提供 `createA2AServer`、任务状态与 Artifact 封装。具体选型以目标 SDK 和小艺开放平台当前技术规范为准。[AgentExtensionAbility API 变更清单](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/js-apidiff-abilitykit-6111)、[AgentHostProxy API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inner-application-agenthostproxy)、[Agent Framework Kit A2A API 变更清单](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/js-apidiff-agentframeworkkit-7002)。
3. **在小艺开放平台注册。**创建端 A2A Agent、关联此应用和模块、填写服务名称、导入 AgentCard、配置示例问题，之后按平台流程调试和上架。[端 A2A 模式文档](https://developer.huawei.com/consumer/cn/doc/service/device-a2a-0000002640106106)。
4. **按需增加应用内的小艺入口。**`FunctionComponent` 可拉起已上线的指定智能体；这属于用户可见对话，不应当作现有 Agent 的后台问答工具。[Agent Framework Kit 接口变更说明](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/js-apidiff-agentframeworkkit-6003)。
5. **需要远程服务时再评估云 A2A。**云端 Remote Agent 要处理平台协议、会话、消息、鉴权与任务结果。AK/SK 应留在服务器；若需访问个人记忆，应设计单独的用户授权与同步机制。[华为云 A2A 开发课程说明](https://developer.huawei.com/consumer/cn/monthly/202608)。

协议报文和 AgentCard 字段应以小艺开放平台最新《AgentCard 定义规范》《端 A2A 协议技术规范》为准，不要直接把现有 OpenAI Chat Completions 工具格式或通用开源 A2A SDK 格式当作小艺协议。平台文档仍有更新。[小艺开放平台文档变更记录](https://developer.huawei.com/consumer/cn/doc/doccenter-celia/update1-0000001238499957)。

## SDK 与手机系统兼容性

当前 `build-profile.json5` 配置：

| 配置 | 当前值 | 作用 |
| --- | --- | --- |
| `targetSdkVersion` | `6.0.2(22)` | 应用声明适配的目标 API，影响部分系统行为和兼容策略。 |
| `compatibleSdkVersion` | `6.0.0(20)` | 应用声明支持的最低系统 API。 |
| `compileSdkVersion` | 未显式指定 | 使用构建工具配套的 SDK；不能仅凭仓库配置推断所有开发机的实际编译版本。 |

本机 DevEco SDK 清单中的 OpenHarmony/HMS ETS 均为 **6.1.1.125、API 24 Release**。这是本机检查结果，不代表项目已经升级或编译成功。

**结论：要在应用中使用 API 24 的 `AgentExtensionAbility`，编译所用 SDK 至少需要提供 API 24 声明。**目前目标 API 22、最低兼容 API 20；建议首先在开发分支验证 API 24 SDK 下的编译与平台接入，再决定是否调整目标 API。API 24 的 AgentCard、AgentHostProxy 等类型与接口均标明从 API 24 起支持。[华为 Ability 公共类型参考](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-app-ability-common)、[AgentHostProxy API](https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/js-apis-inner-application-agenthostproxy)。

**提高编译 SDK 或目标 API，不必自动提高最低兼容 API。**华为升级指南说明，可用 `compatibleSdkVersion` 保留对较早系统的支持；但新 API 在未升级的设备上可能不可用，需要做兼容处理，并在新旧系统设备上验证。[华为应用升级与适配指南](https://developer.huawei.com/consumer/en/doc/harmonyos-releases/upgrade-adaptation)。因此可研究保持最低兼容 API 20：API 24 以下继续运行原有聊天和记忆功能，隐藏或禁用端 A2A 入口；API 24 及以上才启用端 A2A。**这需要实际验证新 Agent Extension 注册在同一应用包内时，API 20～23 系统仍能安装、启动、使用旧功能**，不能只依赖代码中的版本判断作保证。

如果直接把 `compatibleSdkVersion` 提高到 API 24，则 API 20～23 手机不再处于该安装包声明的兼容范围，旧系统用户需要升级手机系统才能安装或更新该版本。现有已安装版本是否继续可用与更新分发是不同问题，应在发布策略中分别处理。旧手机能否升级到 API 24 则取决于其设备型号和系统更新支持。

另需区分 API 24 的底层 Agent Extension 与较新的 `createA2AServer` 封装；后者不能反推前者一定要求 API 26。小艺开放平台的实际端 A2A 准入版本、可调用范围及设备侧支持，仍需在平台配置与目标手机上确认。若平台要求更高系统版本，旧手机仍可保留普通 App 功能，但不能使用相应的小艺端侧能力。

## 建议验证清单

1. 确认小艺开放平台当前端 A2A 技术规范和最低设备系统要求。
2. 用 API 24 SDK 做独立的 Agent Extension 最小样例，保持最低兼容 API 20，检查编译告警与打包结果。
3. 在 API 20～23 与 API 24+ 设备上分别验证安装、冷启动、原有聊天和记忆查询；在支持的设备上验证小艺调用、身份校验与撤销授权。
4. 对身份证号、地址等敏感记忆做逐项授权、结果脱敏和调用记录；对 GUI 副作用继续执行现有确认流程。

本调研没有修改 SDK 配置、安装应用或运行构建。
