# Workflow Mock 源数据

本目录保存 Workflow 与“数据归家”流程验证用的源级 mock 数据。

## 生成

```bash
python3 scripts/mock/generate_workflow_mock.py
```

默认输出：

- `mock/workflows-source/daily-log/YYYY-MM-DD/*.md`
- 内置确定性数据覆盖外卖、购物、聊天、社交内容、出行、生活服务和娱乐等领域。

通过 LLM 追加生成更多条目：

```bash
python3 scripts/mock/generate_workflow_mock.py --llm-count 100 --llm-domains takeout,shopping,chat,travel
```

LLM 默认配置：

- API URL: `http://123.60.91.241:9003/v1/models`
- Model: `Qwen3.5-35B-A3B`
- API key: 空
- 默认关闭 Qwen thinking 输出：`chat_template_kwargs.enable_thinking=false`
- 默认采样参数：`max_tokens=16384`、`temperature=0.7`、`top_p=0.8`、`presence_penalty=1.5`、`top_k=20`

生成器会把 `/v1/models` 归一化为 `/v1/chat/completions` 后发起 chat completion 请求。
只有 `--llm-count` 大于 `0` 时才会访问网络。

可选生成轻量运行摘要：

```bash
python3 scripts/mock/generate_workflow_mock.py --include-runs
```

## 校验

```bash
python3 scripts/mock/generate_workflow_mock.py --validate-only
python3 -m unittest scripts.mock.test_generate_workflow_mock
```

## 导入设备

```bash
python3 scripts/mock/import_workflow_mock.py
```

可选导入运行摘要：

```bash
python3 scripts/mock/import_workflow_mock.py --include-runs
```

导入脚本会把数据发送到：

```text
/data/storage/el2/base/haps/entry/files/workflows
```

导入后打开 App，并触发 App 内同步/分析流程。`profile-consolidation/outputs`、`indexes`、
`profile` 和 `collection-groups` 应由 App 自己生成。

## 边界

不要在这里提交或导入 mock `profile-consolidation` 数据。这些文件是派生结果，
应由 App 分析管线从 `daily-log` 源文件生成。
