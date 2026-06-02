# AGENTS.md

本文件给后续在本仓库工作的代码代理使用。优先遵守用户的直接指令；如果本文件与 `AGENT.md` 有差异，以更具体、更新的上下文为准，并在改动时保持两个文件不要互相矛盾。

## Project Overview

这是一个 HarmonyOS NEXT / ArkTS 工程，应用名源自 MobiInfer LLM Chat。项目目标是把端侧大模型推理、HarmonyOS App UI、PC 侧 HDC 控制服务和视觉自动化 Agent 串起来。

主要运行链路：

- HarmonyOS App：`entry` 模块，ArkTS 页面与状态管理在 `entry/src/main/ets`。
- NAPI/C++ 推理桥：`entry/src/main/cpp` 编译为 `libentry.so`，链接 MNN、HiAI/NNRT 相关库。
- PC 辅助端：`entry/src/main/python` 提供模型文件服务、HDC 代理和自动化 Agent。
- 模型与原生库：`entry/libs/arm64-v8a` 和 `entry/src/main/cpp/include` 中包含二进制库与头文件，更新时要和模型/SDK 版本对应。

## Important Paths

- `entry/src/main/ets/pages/Index.ets`：主入口页面，持有顶层状态、底部 tab、本地推理、模型下载、HDC 触发、云端 Planner/Decider 配置等逻辑。
- `entry/src/main/ets/components/AppHeader.ets`：共享头部组件。
- `entry/src/main/ets/pages/home/HomePage.ets`、`collection/CollectionPage.ets`、`task/TaskPage.ets`：主要 tab UI。
- `entry/src/main/ets/utils/LlmServer.ets`：App 端 TCP 服务，和 PC 侧 Agent 用 `<<EOF>>` 分隔 JSON 消息。
- `entry/src/main/ets/utils/CloudModelClient.ets`、`CloudDeciderPrompt.ets`：OpenAI-compatible `/v1/chat/completions` 云端 Planner/Decider 客户端与提示词。
- `entry/src/main/cpp/napi_init.cpp`：`libentry.so` 的 NAPI 导出、本地 LLM 生命周期、日志捕获和 Agent 推理接口。
- `entry/src/main/cpp/HIAIModelManager.*`：HiAI/NNRT 相关模型管理。
- `entry/src/main/cpp/types/libentry/Index.d.ts`：ArkTS 侧引用 `libentry.so` 的类型声明。
- `entry/src/main/python/hdc_server.py`：PC 端 9124 HTTP 服务，接收 App 下发的 HDC 命令，并按需拉起 `harmony_agent.py`。
- `entry/src/main/python/harmony_agent.py`：PC 端视觉自动化 Agent，负责截图、提示词组织、决策、HDC/hmdriver2 操作。
- `entry/src/main/python/prompts`：Planner、Decider、Grounder、E2E Agent 提示词模板。
- `entry/src/test`、`entry/src/ohosTest`：Hypium 单元测试和设备测试样例。

## Build And Run

优先使用 DevEco Studio 打开仓库根目录进行签名、构建、安装和预览。根配置为：

- `oh-package.json5`：工程级依赖，当前主要是 Hypium/Hamock 测试依赖。
- `entry/oh-package.json5`：模块级依赖，声明 `libentry.so` 文件依赖。
- `build-profile.json5`：产品、签名、SDK、strict mode 配置。
- `entry/build-profile.json5`：entry 模块 CMake/native build 配置。
- `hvigorfile.ts`、`entry/hvigorfile.ts`：Hvigor 任务入口。

命令行构建依赖本机 DevEco/Hvigor 环境、签名配置和可能的网络下载。在 Codex 沙箱中可能因为 `.hvigor` 写入、用户目录写入或网络受限失败。不要反复盲目重试；记录失败信息，并让用户用 DevEco 本地运行，或在允许时请求提升权限。

PC 辅助端常用命令：

```bash
pip install Pillow hmdriver2
python entry/src/main/python/serve_model.py
python entry/src/main/python/hdc_server.py
python entry/src/main/python/hdc_server.py --no_reason
```

HDC 需要能在终端执行 `hdc list targets`。无线调试、模型下载服务和 HDC 服务通常分别使用 README 中的 9123、9124、9126 端口链路。

## Verification

根据改动范围选择验证方式：

- ArkTS UI/业务改动：优先用 DevEco Studio 构建或预览；如果无法运行，至少检查相关 `.ets` 类型、导入和状态流。
- NAPI/C++ 改动：确认 `entry/src/main/cpp/CMakeLists.txt`、`Index.d.ts`、ArkTS 调用点一致；需要 DevEco native build 验证。
- Python Agent 改动：可用本机 Python 做语法检查，例如 `python -m py_compile entry/src/main/python/hdc_server.py entry/src/main/python/harmony_agent.py`，但真实验证仍依赖已连接 HarmonyOS 设备和 `hdc`。
- 提示词改动：说明影响的 Agent 模式和期望输出 JSON/action 格式，不要只做文案改动后假设行为正确。
- 测试文件目前多为模板样例；新增实质逻辑时补充聚焦测试或说明无法自动化验证的原因。

## Coding Guidelines

ArkTS:

- 保持严格 ArkTS 兼容。避免 `any` 和 `unknown`，必要时定义显式 interface/type。
- `catch` 不写类型标注；使用 `catch (e) { let err = e as Error; ... }`。
- JSON 解析/序列化优先使用 `import { JSON as ArkJSON } from '@kit.ArkTS'`。
- 函数返回类型尽量显式，尤其是工具方法、异步方法和跨组件传入的回调。
- UI 文本、按钮和卡片要适配 1080 x 2340 手机预览，避免固定过宽布局；长文本使用 `maxLines` 和 `textOverflow`。
- 不要在一个 `@Entry` 组件里引入重复 `build()`。

C++ / NAPI:

- 改动导出函数时同步更新 `entry/src/main/cpp/types/libentry/Index.d.ts` 和 ArkTS 调用点。
- 保持日志捕获、模型生命周期和全局状态线程安全；涉及 `g_llm`、`g_messages`、`g_mutex` 时谨慎处理并发。
- `entry/libs/arm64-v8a/*.so` 和 `entry/src/main/cpp/include` 是大体积/SDK 绑定资产，除非任务明确要求，不要替换或格式化。

Python:

- `harmony_agent.py` 同时承担设备选择、端口转发、截图、提示词加载、动作执行和任务收尾；改动前先定位具体链路。
- HDC 命令可能在 Windows/macOS/Linux 上运行，避免写死只适用于单一 shell 的命令，已有 `NULL_DEVICE`、`HDC_TARGET`、`hdc_prefix()` 等兼容逻辑要保留。
- 不要改变 `<<EOF>>` 消息边界、9126 本地 TCP 通信协议或动作 JSON 格式，除非同步修改 App 端 `LlmServer.ets`。

## Product And Behavior Constraints

- 现有本地推理逻辑必须保留，除非用户明确要求改动。重点保护：`prepareCustomOpp`、`mnnllm.loadModel`、`mnnllm.generate`、`mnnllm.chat`、`mnnllm.reset`、`LlmServer.start`、模型下载/配置/调试 helper、`pages/OpTest` 与 `pages/LogView` 导航。
- App 曾被改造成“数据归家”相关 UI。做 UI 调整时，优先保持 `HomePage`、`CollectionPage`、`TaskPage` 的职责分离，不要把所有 UI 重新塞回 `Index.ets`。
- 云端模型客户端按 OpenAI-compatible chat completions URL 规范拼接 `/v1/chat/completions`；变更 URL 逻辑时要兼容 base URL 以 `/v1` 或 `/chat/completions` 结尾的情况。
- Agent 执行动作具有真实设备副作用。默认不要自动扩大授权、自动点击高风险动作或绕过确认逻辑。

## Repository Hygiene

- 当前仓库可能已有用户未提交改动；修改前后都用 `git status --short` 确认范围，不要还原非本任务产生的变更。
- 根目录 `build-profile.json5` 包含本机签名材料路径和密码样式字段。不要把这些值复制到日志、issue、PR 描述或新文档中；如果需要讨论，只说“本机签名配置”。
- 不要提交 `oh_modules`、`build`、`.hvigor`、`.preview`、`.cxx`、本地模型权重、截图缓存或设备生成日志。
- 保持 `README.md` 面向用户使用说明，`AGENTS.md` 面向代码代理维护说明；需要同步的重要约定可以简短重复，但不要让两处长期冲突。
