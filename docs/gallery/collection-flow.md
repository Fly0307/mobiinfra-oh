# Gallery Collection Flow

图库采集有两个入口：手动选择图片采集和自动全库分析。两者共用同一套分析管线和存储格式。

## Manual Selection

手动选择图片采集使用系统图片选择器：

```text
PhotoViewPicker -> photoUris[] -> GalleryAnalyzer.analyzeUris(...)
```

行为：

- 用户显式选择图片。
- 当前选择上限由页面传入，现阶段为 9 张。
- picker 只返回 URI，因此如果没有额外 asset 元数据，归档日期会退回到分析日期。
- 每张图片进入分析前仍会检查 `items/<date>/<id>.json`，命中缓存时跳过后续分析。

适用场景：

- 调试 OCR / 大模型 / embedding 效果。
- 小批量补采。
- 用户只想分析某几张图片。

## Automatic Full Library Analysis

自动分析不使用系统图片选择器，而是直接读取图库 asset 列表：

```text
photoAccessHelper.getPhotoAccessHelper(context)
  -> getAssets(...)
  -> GalleryAnalyzer.analyzeInputs(...)
```

当前策略：

- 需要 `ohos.permission.READ_IMAGEVIDEO` 权限。
- 扫描图库全量图片。
- 按 `PhotoKeys.DATE_ADDED` 倒序读取。
- 从 asset 中读取 `DATE_ADDED`，失败时再尝试 `DATE_MODIFIED`。
- 生成 `GalleryPhotoInput`，包含 `uri`、稳定 `id` 和归档 `date`。
- 自动扫描开始时创建 `scan-session.json` 队列。
- 每张图片先检查 `items/<date>/<id>.json`。
- 缓存命中时跳过图片解码、OCR、大模型和 embedding。
- 缓存未命中时完整执行 OCR、大模型分析、embedding 和落盘。

## Pause And Resume

自动全库分析支持暂停和继续。

暂停行为：

- 暂停是软暂停。
- 已经开始的 OCR、模型请求、embedding 和文件写入会继续完成。
- 当前并发任务完成后，不再领取新的图片。
- 每张图片完成后都会更新 `scan-session.json`。
- 剩余图片保持 `queued` 状态。

继续行为：

- 页面读取 `scan-session.json`。
- 把 `queued` 和上次临时失败的 `failed` 图片重新送入分析管线。
- `done`、`skipped` 不会重复处理。
- 每张重新送入的图片仍会先检查 `items/<date>/<id>.json`，命中成功缓存则转为 `skipped`。

进度统计：

- `总数`：本次全库扫描生成的图片数量。
- `已完成`：`done + skipped`。
- `未完成`：尚未完成的图片数量，包含未领取、正在执行和上次失败待重试的任务。
- `跳过`：命中缓存或 OCR 关键词预筛过滤的图片数量。
- `失败`：分析失败的图片数量。

## Shared Pipeline

两个入口最终都会进入同一条分析管线：

1. 生成或接收稳定图片 `id` 和归档 `date`。
2. 检查 `gallery-log/items/<date>/<id>.json`。
3. 命中缓存则直接复用 item JSON。
4. 未命中缓存则解码图片。
5. 按设置执行或跳过鸿蒙本地 OCR。
6. 调用云端多模态模型，解析 `title/category/summary/tags`。
7. 对标题、类别、摘要和 OCR 文本拼接后做 embedding。
8. 写入 `embeddings/<date>/<id>.json`。
9. 写入 `items/<date>/<id>.json`。
10. 批次结束后，从本批次涉及日期的 items 重建 daily-log markdown。

## Operational Notes

自动全库分析可能覆盖几千张图片，首次运行会产生大量 OCR、模型和 embedding 工作。缓存命中能避免重复处理，但首次冷启动仍然需要较长时间。

后续建议补充：

- 失败重试队列。
- 后台进度持久化。
- 仅 Wi-Fi / 充电时运行。
