# 汇总页分组标题规范设计

## 背景

当前汇总页的分组标题由模型分组、启发式分组和增量复用共同产生，缺少统一的最终标题策略。真实数据中已经出现几类问题：

- 聊天 tab 将地点、商户、页面或脚本误当成对话对象，例如“与苏州的对话”“与饿了么的对话”“与HDC导入脚本的对话”。
- 不同 tab 的标题粒度不一致。外卖页已经接近“应用-事件”的形式，购物、娱乐、生活、社交、差旅仍混合使用平台名、事实短句和泛称。
- 组标题和详情页实际内容有时不对应。用户希望组标题用于快速扫读，组内 entry 标题保持事实原貌，不做强制统一。

## 目标

新增一个汇总页分组标题策略层，将每个 tab 的“组标题”统一成稳定、可读、与详情事实对应的格式：

- 普通业务 tab 使用“应用/来源-事件/事实”。
- 聊天 tab 使用“联系人/群聊-事件/事实”。
- 图库补充 tab 使用“类型/来源-图片事实”。

本轮不改变 tab 归属策略：微信聊天中提到的外卖、购物、出行、工作事项仍保留在聊天 tab，以会话视角展示。

## 标题规范

| Tab | 组标题格式 | 示例 |
| --- | --- | --- |
| 购物 | `应用/来源-商品/订单/物流/售后` | `淘宝-耐克跑鞋浏览`、`京东-键盘退换货`、`支付宝-天猫超市消费` |
| 外卖 | `外卖平台-门店/商品/订单` | `美团外卖-黄焖鸡`、`饿了么-叮咚买菜`、`饿了么-快悠汇超市` |
| 娱乐 | `平台-内容/行为` | `哔哩哔哩-苏州旅行Vlog`、`腾讯视频-篮球回放` |
| 聊天 | `联系人/群聊-事件/事实` | `小赵-Bug修复与PR`、`产品群-HDC脚本优化`、`小赵-苏州购机计划` |
| 生活 | `应用/来源-生活事件` | `华为运动健康-步数记录`、`美团-生活服务` |
| 社交 | `平台-内容主题` | `小红书-苏州旅游攻略`、`微博-新能源汽车` |
| 差旅 | `应用-路线/目的地/票务/酒店` | `高德地图-杭州东站导航`、`携程-上海至苏州高铁` |
| 图库补充 | `图库-图片事实/分类主题` | `图库-室内人物`、`图库-文档记录`、`图库-办公截图` |

## 聊天标题规则

聊天 tab 保持会话视角，标题由两部分组成：

1. 会话对象：优先从 `sources[1]`、source ref 文件名末段、`联系人：`、`会话标题：`、`微信联系人「...」` 提取。群聊保留群名，例如 `产品群`、`WAIC群聊`。
2. 事件主题：优先复用当前组标题中已有的有效事件词；否则从组内事件的 summary、keywords、todo 文本中提取一个短主题。

禁止把以下内容作为会话对象：

- `place` 实体，例如 `苏州`、`数据归家首页`。
- `merchant` 实体，例如 `饿了么`、`美团外卖`。
- 页面、脚本、数据、截图、图片、日期、run id、图库 item id、泛称“微信”“聊天”“图库”。

当无法识别会话对象时，聊天标题降级为 `微信-事件主题` 或 `图库聊天-事件主题`，不再生成“与...的对话”。

## 架构

在 DataManager 分组流程中新增标题策略层，建议命名为 `CollectionGroupTitlePolicy`，负责：

- 输入 `tabId`、`CollectionGroupState`、组内 `IndexedEvent[]`。
- 输出规范化后的 `group.title`。
- 只处理组标题，不修改组内 event、entry 标题和详情内容。

接入点：

- `normalizeCollectionGroups()`：覆盖模型全量分组和启发式分组。
- `finalizeIncrementalCollectionGroups()`：覆盖增量复用和新增分组。
- 标题规范化后再做同标题合并，避免相同事件被拆成重复组。

## 数据流

1. daily-log 被 consolidation/index 流程转换为 `IndexedEvent`。
2. collection grouping 先按 tab query 选取事件。
3. 模型或启发式逻辑生成候选 group。
4. 标题策略层读取 group 和组内事件，生成规范标题。
5. 同标题、同来源语义接近的 group 合并。
6. 写入 `profile-consolidation/indexes/collection-groups/<tab>.json`，前端继续按现有字段展示。

## 错误处理与兼容

- 如果标题策略无法提取来源或事件主题，使用 tab 默认兜底标题，例如 `微信-聊天记录`、`购物-相关记录`、`图库-图片记录`。
- 保留已有 `group_id` 稳定策略，但 bump collection grouping input hash 版本，让旧坏标题在下次 refresh 时重建。
- 兼容历史分组文档：即使旧文档已有 `与wechat-...的对话`、`与聊天的对话` 或 `与苏州的对话`，加载/刷新时也会被标题策略改写。

## 测试计划

新增 ArkTS 单元测试覆盖：

- 聊天普通联系人：`小赵 + Bug修复与PR` 生成 `小赵-Bug修复与PR`。
- 聊天群聊：`产品群 + HDC脚本优化` 生成 `产品群-HDC脚本优化`。
- 聊天禁用实体对象：`place:苏州`、`merchant:饿了么` 不得生成 `与苏州的对话` 或 `与饿了么的对话`。
- 微信自动采集：`微信联系人「小赵」`、`联系人：小赵`、`会话标题：小赵` 均能提取 `小赵`。
- 图库聊天：无明确联系人时生成 `图库聊天-事件主题` 或 `微信截图-事件主题`。
- 外卖、购物、娱乐、生活、社交、差旅标题均符合 `来源-事件` 形式。
- 增量分组复用旧标题时也会刷新为新规范。

验证命令：

- `git diff --check`
- Hvigor 单元测试：
  `env DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk JAVA_HOME=/Applications/DevEco-Studio.app/Contents/jbr PATH=/Applications/DevEco-Studio.app/Contents/jbr/Contents/Home/bin:$PATH /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js test --mode module -p module=entry@default -p product=default --no-daemon`

## 非目标

- 不改变各 tab 的事件归属策略。
- 不强制重写详情页中每条 entry 的标题。
- 不引入跨 tab 去重或双入口展示。
- 不重构 DataManager 全流程，只在 collection grouping 的标题生成边界内收敛行为。
