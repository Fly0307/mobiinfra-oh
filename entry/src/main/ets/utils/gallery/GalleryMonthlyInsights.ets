import { GalleryAnalysisResult } from './GalleryTypes';

export interface GalleryMonthlyCategoryCount {
  label: string;
  count: number;
}

export interface GalleryMonthlyInsight {
  key: string;
  label: string;
  totalCount: number;
  categoryCounts: GalleryMonthlyCategoryCount[];
  representativeItems: GalleryAnalysisResult[];
  entriesForLlm: GalleryAnalysisResult[];
  summary: string;
}

interface GalleryMonthBucket {
  key: string;
  label: string;
}

export class GalleryMonthlyInsights {
  static build(results: GalleryAnalysisResult[]): GalleryMonthlyInsight[] {
    let buckets: Record<string, GalleryAnalysisResult[]> = {};
    let labels: Record<string, string> = {};
    for (let i = 0; i < results.length; i++) {
      let bucket = GalleryMonthlyInsights.monthBucket(results[i]);
      labels[bucket.key] = bucket.label;
      if (!buckets[bucket.key]) {
        buckets[bucket.key] = [];
      }
      buckets[bucket.key].push(results[i]);
    }

    let insights: GalleryMonthlyInsight[] = [];
    let keys = Object.keys(buckets);
    for (let i = 0; i < keys.length; i++) {
      let key = keys[i];
      let items = buckets[key].slice(0);
      items.sort((left: GalleryAnalysisResult, right: GalleryAnalysisResult) => {
        let rightTime = GalleryMonthlyInsights.itemTime(right);
        let leftTime = GalleryMonthlyInsights.itemTime(left);
        if (rightTime !== leftTime) {
          return rightTime - leftTime;
        }
        return right.createdAt - left.createdAt;
      });
      let categoryCounts = GalleryMonthlyInsights.tagCounts(items);
      insights.push({
        key: key,
        label: labels[key],
        totalCount: items.length,
        categoryCounts: categoryCounts,
        representativeItems: items.slice(0, Math.min(6, items.length)),
        entriesForLlm: items,
        summary: GalleryMonthlyInsights.summary(labels[key], items.length, categoryCounts)
      });
    }
    insights.sort((left: GalleryMonthlyInsight, right: GalleryMonthlyInsight) => right.key.localeCompare(left.key));
    return insights;
  }

  static buildLlmInput(insight: GalleryMonthlyInsight): string {
    let limit = Math.min(80, insight.entriesForLlm.length);
    let lines: string[] = [];
    lines.push('月份：' + insight.label);
    lines.push('总数：' + insight.totalCount.toString());
    lines.push('标签分布：' + GalleryMonthlyInsights.categoryCountText(insight.categoryCounts));
    lines.push('本地初步摘要：' + insight.summary);
    lines.push('图片摘要清单：共 ' + insight.totalCount.toString() + ' 张，本次提供 ' + limit.toString() +
      (insight.totalCount > limit ? ' 张代表样本。' : ' 张全部样本。'));
    for (let i = 0; i < limit; i++) {
      let item = insight.entriesForLlm[i];
      let timeText = item.date && item.date.length > 0 ? item.date : GalleryMonthlyInsights.formatDate(item.createdAt);
      let tagText = GalleryMonthlyInsights.displayTags(item).join('、');
      if (tagText.length === 0) {
        tagText = item.category && item.category.length > 0 ? item.category : '其他';
      }
      let text = GalleryMonthlyInsights.compactText((item.title ? item.title : '') + ' ' + (item.summary ? item.summary : ''), 120);
      lines.push('- ' + timeText + '｜' + tagText + '｜' + text);
    }
    if (limit === 0) {
      lines.push('无');
    }
    return lines.join('\n');
  }

  private static monthBucket(item: GalleryAnalysisResult): GalleryMonthBucket {
    let dateText = item.date && item.date.length >= 7 ? item.date : '';
    if (dateText.length >= 7) {
      let year = dateText.substring(0, 4);
      let monthText = dateText.substring(5, 7);
      let monthNumber = parseInt(monthText);
      if (year.length === 4 && !isNaN(monthNumber) && monthNumber >= 1 && monthNumber <= 12) {
        return {
          key: year + '-' + monthText,
          label: year + '年' + monthNumber.toString() + '月'
        };
      }
    }
    let ts = item.createdAt;
    if (ts > 0) {
      let date = new Date(ts);
      let year = date.getFullYear().toString();
      let monthNumber = date.getMonth() + 1;
      let monthText = monthNumber.toString().padStart(2, '0');
      return {
        key: year + '-' + monthText,
        label: year + '年' + monthNumber.toString() + '月'
      };
    }
    return {
      key: '0000-00',
      label: '时间未知'
    };
  }

  private static itemTime(item: GalleryAnalysisResult): number {
    let dateText = item.date && item.date.length >= 10 ? item.date : '';
    if (dateText.length >= 10) {
      let parsed = new Date(dateText + ' 00:00:00').getTime();
      if (!isNaN(parsed)) {
        return parsed;
      }
    }
    return item.createdAt;
  }

  private static tagCounts(items: GalleryAnalysisResult[]): GalleryMonthlyCategoryCount[] {
    let counts: Record<string, number> = {};
    for (let i = 0; i < items.length; i++) {
      let tags = GalleryMonthlyInsights.displayTags(items[i]);
      for (let j = 0; j < tags.length; j++) {
        counts[tags[j]] = counts[tags[j]] ? counts[tags[j]] + 1 : 1;
      }
    }
    let result: GalleryMonthlyCategoryCount[] = [];
    let keys = Object.keys(counts);
    for (let i = 0; i < keys.length; i++) {
      result.push({
        label: keys[i],
        count: counts[keys[i]]
      });
    }
    result.sort((left: GalleryMonthlyCategoryCount, right: GalleryMonthlyCategoryCount) => right.count - left.count);
    return result;
  }

  private static displayTags(item: GalleryAnalysisResult): string[] {
    let tags: string[] = [];
    if (item.tags) {
      for (let i = 0; i < item.tags.length && tags.length < 4; i++) {
        let tag = GalleryMonthlyInsights.cleanTag(item.tags[i]);
        if (tag.length > 0 && !GalleryMonthlyInsights.contains(tags, tag)) {
          tags.push(tag);
        }
      }
    }
    if (tags.length === 0) {
      let fallback = GalleryMonthlyInsights.categoryLabel(item.category);
      if (fallback.length > 0) {
        tags.push(fallback);
      }
    }
    return tags;
  }

  private static cleanTag(value: string): string {
    let tag = value ? String(value).replace(/[#，。！？、；：,.!?;:\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim() : '';
    if (tag.length > 12) {
      return tag.substring(0, 12);
    }
    return tag;
  }

  private static contains(items: string[], target: string): boolean {
    for (let i = 0; i < items.length; i++) {
      if (items[i] === target) {
        return true;
      }
    }
    return false;
  }

  private static categoryLabel(category: string): string {
    let value = category ? String(category).trim() : '';
    if (value === '餐饮' || value === '出行' || value === '购物' || value === '健康' ||
      value === '文档' || value === '聊天' || value === '工作') {
      return value;
    }
    return '其他';
  }

  private static summary(monthLabel: string, totalCount: number, categoryCounts: GalleryMonthlyCategoryCount[]): string {
    let topLabels: string[] = [];
    let topLimit = Math.min(3, categoryCounts.length);
    for (let i = 0; i < topLimit; i++) {
      topLabels.push(categoryCounts[i].label);
    }
    let top = topLabels.join('、');
    let leading = top.length > 0 ?
      monthLabel + ' 共分析 ' + totalCount.toString() + ' 张图片，主要集中在 ' + top + '。' :
      monthLabel + ' 共分析 ' + totalCount.toString() + ' 张图片。';
    if (categoryCounts.length > 0 && categoryCounts[0].count >= Math.max(3, Math.floor(totalCount / 2))) {
      return leading + '高频标签比较集中，适合围绕“' + categoryCounts[0].label + '”先整理代表图片。';
    }
    if (categoryCounts.length >= 3) {
      return leading + '标签分布较分散，可以先查看代表图片，再按主题拆分归档。';
    }
    return leading + '可以先查看代表图片，再决定是否按月份归档。';
  }

  private static categoryCountText(categoryCounts: GalleryMonthlyCategoryCount[]): string {
    let parts: string[] = [];
    for (let i = 0; i < categoryCounts.length; i++) {
      parts.push(categoryCounts[i].label + '=' + categoryCounts[i].count.toString());
    }
    return parts.length > 0 ? parts.join('、') : '无';
  }

  private static compactText(text: string, maxLength: number): string {
    let value = text.replace(/[\r\n\t]+/g, ' ').replace(/\s+/g, ' ').trim();
    if (value.length <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength);
  }

  private static formatDate(ts: number): string {
    if (ts <= 0) {
      return '';
    }
    let date = new Date(ts);
    let y = date.getFullYear();
    let m = (date.getMonth() + 1).toString().padStart(2, '0');
    let d = date.getDate().toString().padStart(2, '0');
    return y.toString() + '-' + m + '-' + d;
  }
}
