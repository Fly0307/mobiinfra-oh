# Local MNN Prompt Loading

本地 MNN Agent 的 prompt 逻辑在 App 侧完成，native 侧只负责执行 `mnnllm.chat`、`agentPrefill`、`agentStep` 等推理接口。

## Agent prompt 文件

Agent 分两段输入本地模型：

- `prefix`: 任务固定部分，先通过 `agentPrefill(prefix)` 预填并缓存 KV。
- `variable`: 每一步变化部分，包含历史、截图标签等，通过 `agentStep(variable)` 继续推理。

App 会优先从当前模型目录读取标准化 prompt 文件：

| 模式 | prefix 文件 | variable 文件 |
| --- | --- | --- |
| reason | `agent_prompt_prefix.md` | `agent_prompt_variable.md` |
| no reason | `agent_prompt_prefix_noreason.md` | `agent_prompt_variable_noreason.md` |

为了兼容已下发的旧模型目录，也会识别下面的 legacy alias。读取优先级始终是标准文件名优先，legacy alias 其次。

| 模式 | legacy prefix 文件 | legacy variable 文件 |
| --- | --- | --- |
| reason | `agent_prefix.md` | `agent_variable.md` |
| no reason | `agent_prefix_noreason.md` | `agent_variable_noreason.md` |

当前模型目录就是本地加载模型使用的 `modelDir`，例如：

- `${filesDir}/model`
- `${filesDir}/modelscope/<owner>__<repo>`

## reason / no reason 选择

`AgentLoopRunner` 启动时仍会向 HDC server 读取 `agentConfig()`，但 HDC config 只作为 fallback。

实际选择优先级如下：

1. 如果模型目录下存在完整 reason prompt set，使用 reason：
   - `agent_prompt_prefix.md`
   - `agent_prompt_variable.md`
2. 否则如果模型目录下存在完整 no-reason prompt set，使用 no reason：
   - `agent_prompt_prefix_noreason.md`
   - `agent_prompt_variable_noreason.md`
3. 如果 reason 和 no-reason 两套都不存在，才 fallback 到 HDC server 的 `agentConfig().no_reason`：
   - `no_reason=true` 时使用 no reason。
   - `no_reason=false`、读取失败或没有明确 boolean 时使用 reason。

这里的“存在”指对应 md 文件可读取且内容非空。选择模式时要求 prefix 和 variable 两个文件都存在，避免只下发半套 prompt 时误切模式。

运行时日志会打印实际选择和加载来源：

- `>> [Agent] prompt mode=reason`
- `>> [Agent] prefix source=<modelDir>/agent_prompt_prefix.md`
- `>> [Agent] variable source=<modelDir>/agent_prompt_variable.md`

如果某个文件走 App 内置 fallback，source 会显示为 `builtin:<旧模板名>`，例如 `builtin:e2e_v2_agent_prefix.md`。

## fallback 规则

读取逻辑在 `AgentPromptTemplates.loadFromModelDir(modelDir, legacyName)`：

1. 根据旧模板名映射到模型目录下的新标准文件名。
2. 如果模型目录下存在对应标准 md，且内容非空，就使用标准文件。
3. 如果标准 md 不存在、为空或读取失败，再尝试 legacy alias。
4. 如果 legacy alias 也不可用，就 fallback 到 App 内置旧 prompt。

旧模板名和新文件名映射如下：

| 旧模板名 | 模型目录标准文件 |
| --- | --- |
| `e2e_v2_agent_prefix.md` | `agent_prompt_prefix.md` |
| `e2e_v2_agent_variable.md` | `agent_prompt_variable.md` |
| `e2e_v2_agent_prefix_noreason.md` | `agent_prompt_prefix_noreason.md` |
| `e2e_v2_agent_variable_noreason.md` | `agent_prompt_variable_noreason.md` |

兼容的 legacy alias 如下：

| 旧模板名 | 模型目录 legacy 文件 |
| --- | --- |
| `e2e_v2_agent_prefix.md` | `agent_prefix.md` |
| `e2e_v2_agent_variable.md` | `agent_variable.md` |
| `e2e_v2_agent_prefix_noreason.md` | `agent_prefix_noreason.md` |
| `e2e_v2_agent_variable_noreason.md` | `agent_variable_noreason.md` |

App 内置 fallback 内容来自 `AgentPromptTemplates.ets`，对应原来的 `entry/src/main/python/prompts/*.md` 内容镜像。

## native 侧模板行为

普通本地 chat 仍会走 native 的 `Llm::response(std::string)`，当 config 里 `use_template=true` 时，MNN tokenizer 会执行 chat template。

本地 Agent 不走 native chat template：

- `agentPrefill` 会设置 `reuse_kv=true`
- `agentPrefill` 会设置 `use_template=false`
- `prefix` 和 `variable` 本身已经由 App prompt 模板拼成模型需要的完整格式

因此 Agent 场景下，模型目录 md 文件需要包含模型期望的角色标记和 special token 格式。
