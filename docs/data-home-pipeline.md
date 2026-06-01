# Daily Log 整理、索引、展示代码梳理

本文档描述当前 HarmonyOS App 中 `daily-log -> consolidated records -> indexes/profile/groups -> UI` 的完整实现。这里的“当前”指 `entry/src/main/ets/datamanager/` 及首页、采集页现有代码，不包含后续 workflow 执行和 daily-log 采集代码。

## 1. 数据根目录和文件布局

### 1.1 固定根目录

运行时数据根目录固定在 App 内部存储：

```text
filesDir/workflows/
```

代码位置：

- `entry/src/main/ets/datamanager/DataManagerPaths.ets:12` 定义 `DataManagerPaths`。
- `entry/src/main/ets/datamanager/DataManagerPaths.ets:21-29` 从 `filesDir` 拼出 `rootDir/dailyLogRoot/outputsRoot/indexesRoot/collectionGroupsRoot/workflowRunsRoot`。
- `entry/src/main/ets/datamanager/DataManagerPaths.ets:32-51` 在 `ensureBaseDirs()` 中创建所有固定目录。

实际目录：

```text
workflows/
  daily-log/
  profile-consolidation/
    outputs/
    indexes/
      events/
      inverted/
      source/
      domain/
      entity/
      temporal/
      profile/
      collection-groups/
  runs/
```

### 1.2 相对路径原则

索引中的路径不保存设备绝对路径。`manifest.json` 写死逻辑根目录：

- `input_root = workflows/profile-consolidation/outputs`
- `index_dir = workflows/profile-consolidation/indexes`
- `run_root = workflows/runs`

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:272-286` 生成 `manifest.json`。
- `entry/src/main/ets/datamanager/DataManagerPaths.ets:72-78` 提供 `relativeToDataManager()` 和 `fromDataManagerRelative()`。
- `entry/src/main/ets/datamanager/DataManagerStorage.ets:216-223` 实现普通相对路径计算。

## 2. 公共类型和核心数据结构

类型集中定义在 `entry/src/main/ets/datamanager/DataManagerTypes.ets`。

### 2.1 daily-log 解析后的类型

- `SourceEntry`：一条 numbered daily-log entry，字段包括 `source_date/file_name/entry_index/entry_text/workflow_metadata/source_ref`。
- `source_ref` 格式为 `YYYY-MM-DD/file.md#entryIndex`。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerTypes.ets:136-143` 定义 `SourceEntry`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:206-208` 生成 `sourceRef()`。

### 2.2 consolidation 中间类型

- `CandidateFact`：从 daily-log entry 拆出的原子事实。
- `AggregatedRecord`：去重合并后的整理记录。
- `ConsolidatedState`：`metadata + records`，写入 `.md.state.json`。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerTypes.ets:145-155` 定义 `CandidateFact`。
- `entry/src/main/ets/datamanager/DataManagerTypes.ets:157-170` 定义 `AggregatedRecord`。
- `entry/src/main/ets/datamanager/DataManagerTypes.ets:172-188` 定义 `ConsolidatedMetadata/ConsolidatedState`。

### 2.3 index/profile/UI 类型

- `IndexedEvent`：索引层事件，是 UI 和查询的核心数据。
- `ProfileState`：首页画像状态。
- `CollectionGroupsDocument`：采集页每个 tab 的分组持久化文档。
- `HomeProfileViewModel`、`CollectionViewModel`、`CollectionGroupViewModel`、`CollectionEventViewModel`：UI adapter 输出。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerTypes.ets:196-214` 定义 `IndexedEvent`。
- `entry/src/main/ets/datamanager/DataManagerTypes.ets:221-250` 定义 `ProfileClaim/ProfileDomainState/ProfileState`。
- `entry/src/main/ets/datamanager/DataManagerTypes.ets:269-288` 定义 `CollectionGroupState/CollectionGroupsDocument`。
- `entry/src/main/ets/datamanager/DataManagerTypes.ets:290-366` 定义首页和采集页 view model。

## 3. App 启动和同步入口

### 3.1 启动初始化

App 进入主页面后，`Index.aboutToAppear()` 会：

1. 读取 `ctx.filesDir`。
2. 初始化本地推理相关路径和 custom op。
3. 调用 `initDataManager()`。

代码位置：

- `entry/src/main/ets/pages/Index.ets:231-245` 启动时调用 `initDataManager()`。
- `entry/src/main/ets/pages/Index.ets:132-141` 创建 `DataManagerFacade(filesDir)`，调用 `ensureReady()`，然后 `reloadDataManagerViewModels()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:123-130` `DataManagerFacade` 构造 `DataManagerStorage/DataManagerPaths/DataPipelineModelClient/ConsolidationService/IndexService/CollectionGroupingService`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:132-136` `ensureReady()` 创建目录并处理清空 marker。

### 3.2 同步按钮

采集页点击“同步”后，回调到主页面：

1. `CollectionPage` 调 `onRefresh()`。
2. `Index.refreshDataManager()` 设置 `dataManagerRefreshing = true`。
3. 调用 `DataManagerFacade.refresh(modelConfig, progress, groupingModelConfig)`。
4. 完成后调用 `reloadDataManagerViewModels()` 重新加载首页和采集页状态。

代码位置：

- `entry/src/main/ets/pages/collection/CollectionPage.ets:139-163` “同步”按钮和回调。
- `entry/src/main/ets/pages/Index.ets:160-197` `refreshDataManager()`。
- `entry/src/main/ets/pages/Index.ets:144-151` `reloadDataManagerViewModels()` 读取首页和采集页 view model。
- `entry/src/main/ets/pages/Index.ets:1640-1663` 主页面把 `homeProfile/collectionViews/onRefresh/onRegroup/refreshing` 传给子页面，并叠加进度浮窗。

### 3.3 进度浮窗

同步期间 `dataManagerRefreshing = true`，页面顶层 `Stack` 显示浮层，阻塞其它 UI 点击。

代码位置：

- `entry/src/main/ets/pages/Index.ets:154-158` 将内部进度折叠为两个阶段：`正在整理日志` 和 `正在构建索引`。
- `entry/src/main/ets/pages/Index.ets:1602-1637` `DataManagerProgressOverlay()`。
- `entry/src/main/ets/pages/Index.ets:1662` 在主 `Stack` 上叠加进度浮窗。

### 3.4 模型配置

当前有两套数据归家模型配置：

- consolidation/index/profile 使用 `cloudPlannerBaseUrl`，默认 `http://166.111.53.96:7003`。
- collection grouping 使用 `dataManagerGroupingBaseUrl`，默认 `http://123.60.91.241:9003`。

代码位置：

- `entry/src/main/ets/pages/Index.ets:71-74` 默认 URL 和 API key。
- `entry/src/main/ets/pages/Index.ets:116-122` `getDataManagerModelConfig()`。
- `entry/src/main/ets/pages/Index.ets:124-130` `getDataManagerGroupingModelConfig()`。
- `entry/src/main/ets/pages/Index.ets:177-179` refresh 时分别传入整理/索引模型和 grouping 模型。

## 4. refresh 总控逻辑

`DataManagerFacade.refresh()` 是完整链路总控。

执行顺序：

1. `ensureReady()`：创建目录，处理清空 marker。
2. `buildDailyLogSnapshot()`：扫描 `daily-log/**/*.md`，计算每个文件 hash 和 entry 数。
3. 如果 snapshot 未变化且已有 generated data，则跳过 consolidation/index，只刷新 collection groups。
4. 否则执行 `ConsolidationService.consolidateAll()`。
5. 执行 `IndexService.build()`。
6. 执行 `CollectionGroupingService.buildAll()`。
7. 写入新的 daily-log snapshot。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerFacade.ets:149-184` `refresh()` 主流程。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:218-244` `buildDailyLogSnapshot()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:246-256` 读写 `daily-log-snapshot.json`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:258-275` 判断是否可跳过 refresh。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:277-289` 跳过时返回 summary。

当前增量行为：

- daily-log 完全不变：跳过 consolidation/index，只检查并复用或重建 collection groups。
- daily-log 新增或文件内容变化：进入 consolidation/index。
- consolidation 会基于每个 entry 的 hash 只处理新增或变更 entry。
- index 会基于 consolidated state 文件 hash 复用未变 source 的已有 events。
- 当前逻辑不是删除感知的：如果 daily-log 删除了旧 entry，已有 consolidated records 不会自动从对应 `.state.json` 中删除；如果需要验证删除效果，应先清空 workflows 后重建。

## 5. daily-log 读取和解析

### 5.1 daily-log 输入格式

输入目录：

```text
workflows/daily-log/YYYY-MM-DD/*.md
```

文件头可包含 metadata 注释：

```markdown
<!-- DAILY_LOG_METADATA
{ ...json... }
-->
1. 第一条记录
2. 第二条记录
```

代码位置：

- `entry/src/main/ets/datamanager/DataManagerUtils.ets:19` metadata 正则。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:159-182` `parseDailyLogDocument()` 解析 metadata，并把正文放到 `body`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:184-204` `parseNumberedEntries()` 按 `1. ...`、`2. ...` 解析 numbered entries。

### 5.2 扫描规则

`ConsolidationService.collectSourceEntries()` 只扫描：

- 目录名匹配 `YYYY-MM-DD` 的 day dir。
- day dir 下后缀为 `.md` 的文件。
- 文件正文中的 numbered entries。

每条 entry 变成 `SourceEntry`，其中：

- `source_date` 来自 day dir。
- `file_name` 来自 markdown 文件名。
- `entry_index` 来自编号。
- `source_ref = source_date/file_name#entry_index`。

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:96-138` 扫描 daily-log 并生成 `SourceEntry`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:206-208` `sourceRef()`。

## 6. Consolidation 整理逻辑

### 6.1 分组粒度和输出文件

整理按 `month + file_name` 分组。也就是说，同一个 daily-log 文件名在同一个月份内会写到同一个 consolidated state。

输出路径：

```text
workflows/profile-consolidation/outputs/YYYY-MM/<file_name>.state.json
workflows/profile-consolidation/outputs/YYYY-MM/<file_name>
```

如果 `file_name` 本身是 `xxx.md`，markdown 输出就是 `xxx.md`，state 是 `xxx.md.state.json`。

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:63-94` `consolidateAll()` 主循环。
- `entry/src/main/ets/datamanager/ConsolidationService.ets:139-158` `groupEntriesByMonth()`。
- `entry/src/main/ets/datamanager/DataManagerPaths.ets:53-59` `outputMarkdownPath()` 和 `outputStatePath()`。

### 6.2 增量 entry 判断

每个 consolidated state 中的 `metadata.processed_entry_hashes` 保存 `source_ref -> sha256(entry_text)`。

`pendingEntries()` 规则：

- 如果某个 `source_ref` 已有 hash，且当前 hash 相同，则跳过。
- 如果某个 `source_ref` 已在已有 records 的 `source_refs` 中出现，也跳过。
- 如果 hash 不同或从未出现，则进入待处理。

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:160-226` `consolidateGroup()` 读取 state、筛 pending、写回 state/markdown。
- `entry/src/main/ets/datamanager/ConsolidationService.ets:270-284` `pendingEntries()`。
- `entry/src/main/ets/datamanager/ConsolidationService.ets:313-335` `buildMetadata()` 写入 `processed_entry_hashes`。

边界说明：

- 这是 append/update 型增量，不是双向同步。
- entry 内容变更会重新处理新内容，但旧内容对应的旧 record 不会被主动删除；只有语义去重判定命中时才会 merge 到已有 record。
- daily-log 删除不会自动删除 old consolidated records。

### 6.3 事实拆分

待处理 entries 会批量调用模型拆分为 `CandidateFact`：

- 模型可用时：`DataPipelineModelClient.splitEntriesIntoFacts()` 以 12 条 entries 为一个 chunk 调用 LLM。
- 模型不可用、请求失败、返回为空：使用 `heuristicSplit()`。
- 模型返回后仍会过 `atomicizeCandidateFacts()`，把包含多笔金额/订单的句子拆成更小事实。

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:172-180` 批量拆分入口。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:284-330` `splitEntriesIntoFacts()`，chunk size 为 12。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:730-755` normalize 模型返回并 atomicize。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:313-346` `heuristicSplit()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:348-483` 金额/订单类原子化拆分。

### 6.4 去重和合并

对每个 `CandidateFact`：

1. 从已有 records 中选出比较范围。
2. 先做 exact match。
3. exact 不命中时，让模型判断 `new/duplicate/merge_with_existing/skip_ambiguous`。
4. 模型不可用或失败时使用 heuristic dedup。
5. 命中已有 record 时调用 `updateExistingRecord()`，否则 `createNewRecord()`。

比较范围：

- 最近 7 天内的 records，或最近 100 条 records，取较小的候选集合。

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:181-210` 每个 fact 的去重处理。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:21-22` `RECENT_MATCH_DAYS = 7`、`RECENT_MATCH_MAX_RECORDS = 100`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:485-502` `selectRecentScopeRecords()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:504-523` `findExactExistingMatch()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:376-420` `decideDedup()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:1124-1157` heuristic dedup。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:610-646` `updateExistingRecord()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:681-697` `createNewRecord()`。

### 6.5 写出的 consolidated markdown

除了 `.state.json`，还会写 markdown 表格，列为：

```text
序号 | 记录日期 | 最近来源日期 | 内容 | 来源条目 | 去重状态
```

代码位置：

- `entry/src/main/ets/datamanager/ConsolidationService.ets:223-224` 写 state 和 markdown。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:703-714` `renderConsolidatedMarkdown()`。

## 7. Index 构建逻辑

`IndexService.build()` 从 `outputs/**/*.md.state.json` 生成所有索引和画像。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:197-295` `build()` 主流程。

### 7.1 读取 consolidated state

索引输入是 `.md.state.json`，不是 markdown 表格。每个 state 文件先算内容 hash。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:199-218` 找 state 文件、读内容、算 digest。

### 7.2 index source 级复用

如果以下条件满足，则直接复用 previous events：

- `manifest` 的输入/输出根目录、enrichment mode/base_url、entity types 一致。
- 当前 state 文件 hash 与 previous manifest 中该 source 的 sha256 一致。
- previous event partitions 中还能找到该 source 的 event ids。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:205-209` 读取 previous manifest/events 并判断 `reuseAllowed`。
- `entry/src/main/ets/datamanager/IndexService.ets:222-235` source 复用分支。
- `entry/src/main/ets/datamanager/IndexService.ets:624-637` `canReuseIndex()`。
- `entry/src/main/ets/datamanager/IndexService.ets:639-649` `canReuseSource()`。

### 7.3 从 record 生成 base event

未复用的 state 会调用 `baseEventsFromState()`。

每条 `AggregatedRecord` 变成一个 `IndexedEvent`：

- `event_id = relativeStatePath#record_id`
- `source_state_file = relativeStatePath`
- `event_date = first_seen_date`
- `last_seen_date = last_seen_date`
- `summary/normalized_fact/tags/source_refs` 来自 record
- `sources` 由 `source_refs` 映射成人类可读来源
- `image_paths` 由 workflow run 的 VLM summary 反查

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:236-244` 未复用时生成 base events 并 enrichment。
- `entry/src/main/ets/datamanager/IndexService.ets:686-723` `baseEventsFromState()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:308-311` `eventSourceNames()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:210-224` `sourceDisplayName()`：保留详细来源，例如联系人名或文件名最后一段。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:226-253` `sourceAppDisplayName()`：仅用于 UI group 来源展示，把 package/task 映射为 App 名。
- `entry/src/main/ets/datamanager/IndexService.ets:725-849` 从 `runs/*/run_summary.json` 反查图片证据路径。

### 7.4 事件 enrichment

模型可用时，`enrichEvents()` 以 16 条 events 为一个 chunk 批量请求，提取：

- `keywords`
- `domains`
- `entities`

模型不可用或 chunk 请求失败时，保留 heuristic 结果。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:238-244` 调用 enrichment。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:441-482` `enrichEvents()`，chunk size 为 16。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:757-768` `heuristicEnrichEvent()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:771-787` 模型输出和 rule 输出合并。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:716-759` 规则关键词和领域。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:861-893` 规则实体。

## 8. 写出的索引文件

### 8.1 events

路径：

```text
workflows/profile-consolidation/indexes/events/YYYY-MM.json
```

内容是 `EventPartition`：

```json
{
  "month": "2026-05",
  "events": [IndexedEvent]
}
```

排序为 `event_date` 升序，同日按 `event_id` 升序。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:254-255` 写 event partitions。
- `entry/src/main/ets/datamanager/IndexService.ets:857-885` `writeEventPartitions()`。

### 8.2 inverted index

路径：

```text
workflows/profile-consolidation/indexes/inverted/index.json
```

`postings` 含义：`term -> event_id[]`。这里的 term 不是完整词，而是归一化文本里的相邻双字/双字符片段。

例如查询“小赵”时，`indexTerms("小赵") = ["小赵"]`，先从 postings 找候选 event id，再用原文包含关系二次校验。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:256` 写 inverted index。
- `entry/src/main/ets/datamanager/IndexService.ets:887-903` `buildInvertedDocument()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:895-917` `indexTerms()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:919-921` `eventSearchText()`：只索引 `summary/normalized_fact/keywords`。

### 8.3 source index

路径：

```text
workflows/profile-consolidation/indexes/source/index.json
```

包含两部分：

- `sources`: `sourceName -> event_id[]`
- `postings`: `sourceName` 归一化后的 term -> event_id[]

这就是为什么保留 `sources` 里的“小赵”等详细来源后，仍可用“小赵”作为 keyword 召回对应事件。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:257` 写 source index。
- `entry/src/main/ets/datamanager/IndexService.ets:905-931` `buildSourceDocument()`。
- `entry/src/main/ets/datamanager/DataManagerUtils.ets:923-925` `sourceSearchText()`。
- `entry/src/main/ets/datamanager/IndexService.ets:319-328` query 中 keyword 同时查 inverted postings 和 source postings。

### 8.4 domain index

路径：

```text
workflows/profile-consolidation/indexes/domain/index.json
```

内容：

- `domains`: 领域说明。
- `postings`: `eat/wear/live/travel/work/other -> event_id[]`。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:258` 写 domain index。
- `entry/src/main/ets/datamanager/IndexService.ets:933-954` `buildDomainDocument()`。

### 8.5 entity index

路径：

```text
workflows/profile-consolidation/indexes/entity/index.json
```

内容：

- `entities`: canonical entity definition，例如 `person:张三`。
- `alias_postings`: `type:normalizedAlias -> entityKey[]`。

构建过程：

1. 收集每个 event 的 `entity_mentions`。
2. 按 type/person/place/merchant 分组。
3. 模型可用时调用 `resolveEntities()` 做同一现实对象归并。
4. 写回每个 event 的 `entities` display keys。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:259-264` 写 entity index，并在满足条件时复用。
- `entry/src/main/ets/datamanager/IndexService.ets:956-1066` `buildEntityDocument()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:503-532` `resolveEntities()`。
- `entry/src/main/ets/datamanager/IndexService.ets:1552-1572` entity 查询。

### 8.6 temporal index

路径：

```text
workflows/profile-consolidation/indexes/temporal/YYYY-MM.json
```

结构：

- month summary
- weeks
- days
- 每层都有 `event_ids` 和 `summary`

summary 复用规则：

- 每个 day/week/month 根据输入内容算 `input_hash`。
- 如果 previous summary 的 hash 一致，则直接复用。
- 否则调用模型 `generateSummary()`；失败或不可用时用 heuristic summary。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:265` 写 temporal documents。
- `entry/src/main/ets/datamanager/IndexService.ets:1113-1214` `writeTemporalDocuments()`。
- `entry/src/main/ets/datamanager/IndexService.ets:1230-1244` `generateTemporalSummary()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:484-500` `generateSummary()`。
- `entry/src/main/ets/datamanager/IndexService.ets:1574-1583` heuristic summary。

### 8.7 profile

路径：

```text
workflows/profile-consolidation/indexes/profile/state.json
workflows/profile-consolidation/indexes/profile/profile.md
```

构建过程：

1. 按 `event.profile_domains || event.domains` 把 events 分到 `eat/wear/live/travel/work/other`。
2. 每个领域算 `input_hash`。
3. 如果 previous domain profile 的 hash 一致，则复用。
4. 否则调用 `DataPipelineModelClient.generateProfile()`。
5. 过滤不合格 claims：空文本、证据少于 2、像单次事件细节、非 `other` 领域的 relation。
6. 写 `state.json` 和 `profile.md`。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:266-270` 生成并写 profile。
- `entry/src/main/ets/datamanager/IndexService.ets:1246-1327` `buildProfileDocument()`。
- `entry/src/main/ets/datamanager/IndexService.ets:1336-1357` `profileDomainInputHash()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:535-572` `generateProfile()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:866-980` profile 分块和 merge。
- `entry/src/main/ets/datamanager/IndexService.ets:1389-1462` normalize/filter profile claims。
- `entry/src/main/ets/datamanager/IndexService.ets:1474-1509` 渲染 `profile.md`，先输出领域 summary，再输出 claim 列表。

## 9. 查询逻辑

### 9.1 查询入口

`IndexService.query(options)`：

1. `queryCandidateIds(options)` 先用索引文件缩小候选集合。
2. `loadEventsByIds(candidateIds)` 只加载候选 event 所在月份的 event partitions。
3. `queryWithEvents(options, events)` 做精确校验、排序和 limit。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:297-301` `query()`。
- `entry/src/main/ets/datamanager/IndexService.ets:408-446` `queryCandidateIds()`。
- `entry/src/main/ets/datamanager/IndexService.ets:383-406` `loadEventsByIds()`。
- `entry/src/main/ets/datamanager/IndexService.ets:303-361` `queryWithEvents()`。

### 9.2 支持的查询条件

`QueryOptions` 支持：

- `keywords`
- `domains`
- `entities`
- `date`
- `month`
- `startDate/endDate`
- `limit`

代码位置：

- `entry/src/main/ets/datamanager/DataManagerTypes.ets:252-260` `QueryOptions`。

### 9.3 keyword 查询

keyword 查询会同时查：

- event 内容索引：`summary/normalized_fact/keywords`
- source 索引：`sources`

执行时先用 postings 找候选，再在原文本上做包含校验，避免仅因 bigram 命中导致误召回。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:415-426` candidate 阶段处理 keywords。
- `entry/src/main/ets/datamanager/IndexService.ets:448-471` keyword postings 候选。
- `entry/src/main/ets/datamanager/IndexService.ets:319-328` 精确阶段处理 keywords。
- `entry/src/main/ets/datamanager/IndexService.ets:1512-1550` `indexedTextMatchIds()`。

### 9.4 domain/date/entity 查询

- domain 查询读取 `domain/index.json` 的 postings。
- date/month/range 查询读取 `temporal/*.json`。
- entity 查询读取 `entity/index.json` 的 alias postings。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:331-339` 精确阶段 domain。
- `entry/src/main/ets/datamanager/IndexService.ets:341-344` 精确阶段 entity。
- `entry/src/main/ets/datamanager/IndexService.ets:473-507` temporal 候选。
- `entry/src/main/ets/datamanager/IndexService.ets:1552-1572` entity 候选。

### 9.5 排序和 limit

最终结果按：

1. `event_date` 倒序。
2. `event_id` 倒序。

`limit <= 0` 表示返回全部匹配事件，主要给采集分组使用。

代码位置：

- `entry/src/main/ets/datamanager/IndexService.ets:346-360` 排序、limit、public event。
- `entry/src/main/ets/datamanager/IndexService.ets:178-184` `resolveQueryLimit()` 和 `isQueryResultTruncated()`。

## 10. 采集页分组逻辑

### 10.1 四个 tab 的查询定义

采集页不直接展示全部 event 列表，而是先用 index 查询出 tab 相关 events，再构建 group。

当前 tab 查询：

- 聊天：`keywords = ["微信"]`
- 购物：`domains = ["eat", "wear", "live", "travel"]`
- 通知：`keywords = ["通知"]`
- 娱乐：`keywords = ["视频"]`

所有 tab 的 `limit = 0`，即返回全部匹配事件供 grouping 使用。

代码位置：

- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:54-80` `collectionTabSpecs()`。

### 10.2 grouping 构建和持久化

`CollectionGroupingService.buildAll()` 对每个 tab：

1. 调用 `indexService.query(spec.query)`。
2. 根据 events 和 model config 计算 `input_hash`。
3. 如果旧文档 hash 一致且有 groups，复用旧分组。
4. 否则调用 Planner LLM 分组。
5. LLM 失败或返回不可用时使用 heuristic fallback。
6. 写入 `indexes/collection-groups/<tabId>.json`。

代码位置：

- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:192-236` `buildAll()`。
- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:248-263` `buildGroupsForTab()`。
- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:265-289` 读取旧文档和计算 `input_hash`。
- `entry/src/main/ets/datamanager/DataManagerPaths.ets:68-70` `collectionGroupsPath()`。

持久化格式：

```json
{
  "generated_at": "...",
  "tab_id": "chat",
  "title": "最近聊天",
  "query": { ... },
  "input_hash": "...",
  "total_events": 88,
  "groups": [
    {
      "group_id": "...",
      "title": "...",
      "source": "...",
      "time": "YYYY-MM-DD",
      "meta": "N 条",
      "status": "已整理",
      "domain": "eat|wear|...",
      "event_ids": ["..."]
    }
  ]
}
```

代码位置：

- `entry/src/main/ets/datamanager/DataManagerTypes.ets:269-288` `CollectionGroupState/CollectionGroupsDocument`。

### 10.3 Planner LLM 分组

`DataPipelineModelClient.planCollectionGroups()`：

- 事件数 <= 80：单次 Planner 请求。
- 事件数 > 80：按 80 条分块生成临时 groups，再调用 merge prompt 合并。
- 聊天 tab 在发给 Planner 前按时间升序排列，让模型看到对话上下文线索。
- prompt 要求按语义接近、上下文连续性、联系人/商户/来源、主题或意图分组，不按日期或平台名分组。

代码位置：

- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:266-276` grouping 和 merge system prompt。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:574-607` `planCollectionGroups()`。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:609-630` 单个 chunk 的 prompt payload 和请求。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:632-643` 聊天 tab 时间升序排序。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:645-702` 分块后的 group merge。
- `entry/src/main/ets/datamanager/DataPipelineModelClient.ets:704-728` normalize Planner 输出。

### 10.4 group 输出校验和 fallback

`normalizeCollectionGroups()` 会保证：

- 只接受输入中存在的 `event_id`。
- 一个 event 最终只进一个 group。
- 空 group 丢弃。
- Planner 漏掉的 event 用 heuristic group 补齐。
- group 按最近 event 时间倒序。
- group id 根据 tab、顺序和 event ids 稳定生成。

代码位置：

- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:120-177` `normalizeCollectionGroups()`。
- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:299-358` heuristic fallback 分组和 `groupFromEvents()`。
- `entry/src/main/ets/datamanager/CollectionGroupingService.ets:397-518` 低信息标题替换和同标题合并。

边界说明：

- heuristic fallback 只应作为兜底，主要依据 source/domain/entity/keyword 做通用分组。
- 当前代码里仍有低信息标题过滤列表，用于防止 Planner 输出“微信聊天记录”“10讨论”等低信息标题；这些逻辑位于 `CollectionGroupingService.ets:473-518`。

## 11. ViewModel 适配逻辑

### 11.1 首页 view model

`loadHomeViewModel()` 读取 `profile/state.json`：

- 无 profile 或 `event_count = 0`：返回 empty home profile。
- 有 profile：四个生活领域吃/穿/住/行读取对应 domain profile。
- `desc` 优先用 domain summary，否则用第一条 claim，否则 `暂无数据`。
- 完整度按吃/穿/住/行四个领域计分：每个有 event 加 18 分；有 summary 或 claims 再加 7 分；满分 100。
- 推荐卡片来自各领域 claims，最多 6 条。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerFacade.ets:63-90` empty 首页 view model 和默认推荐。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:314-340` `loadHomeViewModel()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:544-555` `domainDescription()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:589-603` `profileCompleteness()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:605-633` `profileRecommendations()`。

### 11.2 采集页 view model

`loadCollectionViewModels()` 返回 4 个 tab 的 view model。

每个 tab：

1. 根据 `collectionTabSpecByIndex(tabIndex)` 做 index query。
2. 读取对应 `collection-groups/<tabId>.json`。
3. 如果没有 persisted groups，则用 heuristic fallback。
4. 根据 group 的 `event_ids` 把 group 和 events 组装成 UI view model。
5. `groups` 是采集页实际展示列表；`rows` 是从 groups 展开的扁平事件列表，目前主要是兼容旧结构。

代码位置：

- `entry/src/main/ets/datamanager/DataManagerFacade.ets:342-350` 加载采集页 view models。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:374-411` `collectionViewModelFromQueryResult()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:413-425` `collectionEventView()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:433-454` `collectionGroupView()`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:456-466` group 小字来源用 `sourceAppDisplayName()` 统一显示 App 名。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:503-541` 采集页领域分布和 summary。

重要兼容点：

- `IndexedEvent.sources` 保留详细来源，例如“小赵”，用于 keyword/source 查询。
- 只有采集页 group 行的小字来源通过 `sourceAppDisplayName(event.source_state_file)` 显示 App 名，例如“微信”。
- group 详情页事件列表仍显示 `CollectionEventViewModel.title/time`，其中事件 source 数据未用于详情卡片展示。

## 12. UI 展示逻辑

### 12.1 首页

首页只接收 `HomeProfileViewModel`，不直接读 index/profile 文件。

展示内容：

- 数字分身更新时间。
- 画像完整度。
- 吃/穿/住/行四个 high-level profile。
- 为你推荐卡片。

代码位置：

- `entry/src/main/ets/pages/home/HomePage.ets:10-12` `profile` 入参。
- `entry/src/main/ets/pages/home/HomePage.ets:129-153` 更新时间和完整度。
- `entry/src/main/ets/pages/home/HomePage.ets:162-175` 吃/穿/住/行。
- `entry/src/main/ets/pages/home/HomePage.ets:177-193` 推荐卡片横向列表。

### 12.2 采集页 group 列表

采集页只接收 `CollectionViewModel[]`，不直接读 index 文件。

展示内容：

- 四个 tab：聊天、购物、通知、娱乐。
- 顶部统计：当前 tab 总事件数、最近同步时间、同步/重分组按钮。
- 中间列表：展示 groups，不直接展示全部 events。
- 底部领域分布和 summary。

代码位置：

- `entry/src/main/ets/pages/collection/CollectionPage.ets:12-18` 入参。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:38-51` tab 控件。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:63-84` group 行 UI 和跳转详情页。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:86-98` 空状态或 group 列表。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:139-180` 同步和重分组按钮。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:188-221` group 列表容器和领域分布。

### 12.3 group 详情页

点击 group 后跳转新页面：

- 路由：`pages/collection/CollectionGroupDetailPage`
- 参数：`tabIndex` 和 `groupId`
- 页面重新创建 `DataManagerFacade`，读取对应 group 的 events。
- 列表项展示事件 `summary` 和时间。
- 长 summary 折叠为 `前 72 字 + ...展开`，点击展开后显示全文并出现 `收起`。

代码位置：

- `entry/src/main/resources/base/profile/main_pages.json:4` 注册详情页。
- `entry/src/main/ets/pages/collection/CollectionPage.ets:75-83` 跳转并传参。
- `entry/src/main/ets/pages/collection/CollectionGroupDetailPage.ets:24-35` 读取路由参数。
- `entry/src/main/ets/pages/collection/CollectionGroupDetailPage.ets:37-48` 通过 `DataManagerFacade.loadCollectionGroupViewModel()` 加载 group。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:352-372` 根据 `tabIndex/groupId` 读取 persisted group 和 events。
- `entry/src/main/ets/pages/collection/CollectionGroupDetailPage.ets:63-128` 详情卡片和展开/收起逻辑。
- `entry/src/main/ets/pages/collection/CollectionGroupDetailPage.ets:130-192` 页面布局和顶部对齐的列表。

## 13. 临时调试脚本

### 13.1 导入 fixture daily-log

脚本：

```powershell
.\scripts\import_daily_log_fixture.ps1
```

默认来源：

```text
D:\repos\MobiAgent\runner\mobiagent\workflow\test-runs\daily-log
```

默认使用：

```text
hdc file send -b com.example.mnnllmchat <source> /data/storage/el2/base/haps/entry/files/workflows
```

代码位置：

- `scripts/import_daily_log_fixture.ps1:1-54`。

### 13.2 导出 App 内 workflows

脚本：

```powershell
.\scripts\export_data_home.ps1
```

导出到：

```text
exports/workflows-YYYYMMDD-HHMMSS/
```

代码位置：

- `scripts/export_data_home.ps1:1-49`。

### 13.3 清空 workflows

脚本：

```powershell
.\scripts\clear_data_home.ps1
```

默认模式不是直接删设备目录，而是把 `.clear-workflows-request.json` marker 发送到 App filesDir。App 下次启动或同步前由 `DataManagerFacade.ensureReady()` 删除并重建 `workflows`。

代码位置：

- `scripts/clear_data_home.ps1:1-77`。
- `entry/src/main/ets/datamanager/DataManagerFacade.ets:138-147` 处理 clear marker。

## 14. 当前实现的明确边界

1. Workflow 定义、执行、相册读取、daily-log 采集不在当前 workflows 层实现范围内。后续只需要写入 `workflows/daily-log/YYYY-MM-DD/*.md`。
2. daily-log 新增是支持增量的；daily-log 删除不是自动反向删除的。
3. LLM 增强全部有 fallback；模型失败不应该导致 UI 崩溃。
4. consolidation/index/profile/grouping 的模型调用目前是分批但顺序 await，不是并发请求池。
5. `source` 在索引事件中保留详细来源，用于查询；采集页 group 行展示 App 名是 UI adapter 行为，不改变索引层 source。
6. 采集页 group 是 index 派生数据，持久化在 `indexes/collection-groups/`，重分组按钮只清理并重建这部分，不重跑 consolidation/index。



