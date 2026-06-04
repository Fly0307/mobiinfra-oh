import { GalleryAnalysisResult } from './GalleryTypes';

export interface GallerySearchHit {
  item: GalleryAnalysisResult;
  score: number;
  reason: string;
}

interface FieldMatch {
  score: number;
  reasons: string[];
}

export class GallerySearchService {
  static search(query: string, items: GalleryAnalysisResult[], limit: number = 20): GallerySearchHit[] {
    let tokens = GallerySearchService.queryTokens(query);
    if (tokens.length === 0) {
      return [];
    }
    let hits: GallerySearchHit[] = [];
    for (let i = 0; i < items.length; i++) {
      let match = GallerySearchService.scoreItem(tokens, items[i]);
      if (match.score > 0) {
        hits.push({
          item: items[i],
          score: match.score,
          reason: GallerySearchService.reasonText(match.reasons)
        });
      }
    }
    hits.sort((left: GallerySearchHit, right: GallerySearchHit) => {
      if (right.score !== left.score) {
        return right.score - left.score;
      }
      return right.item.createdAt - left.item.createdAt;
    });
    return hits.slice(0, Math.min(limit, hits.length));
  }

  private static scoreItem(tokens: string[], item: GalleryAnalysisResult): FieldMatch {
    let result: FieldMatch = { score: 0, reasons: [] };
    GallerySearchService.scoreField(tokens, item.title, 10, '标题', result);
    GallerySearchService.scoreField(tokens, item.category, 8, '类别', result);
    GallerySearchService.scoreField(tokens, item.tags ? item.tags.join(' ') : '', 9, '标签', result);
    GallerySearchService.scoreField(tokens, item.summary, 6, '摘要', result);
    GallerySearchService.scoreField(tokens, item.details ? item.details.join(' ') : '', 5, '细节', result);
    GallerySearchService.scoreField(tokens, item.ocrText, 3, 'OCR', result);
    GallerySearchService.scoreField(tokens, item.date, 4, '日期', result);
    if (result.score > 0) {
      result.score += GallerySearchService.recencyBoost(item.createdAt);
    }
    return result;
  }

  private static scoreField(tokens: string[], value: string, weight: number, label: string, result: FieldMatch): void {
    let text = GallerySearchService.normalize(value);
    if (text.length === 0) {
      return;
    }
    let matched = 0;
    for (let i = 0; i < tokens.length; i++) {
      if (text.indexOf(tokens[i]) >= 0) {
        matched += 1;
      }
    }
    if (matched > 0) {
      result.score += matched * weight;
      GallerySearchService.pushUnique(result.reasons, label + '命中');
    }
  }

  private static queryTokens(query: string): string[] {
    let normalized = GallerySearchService.normalize(query);
    if (normalized.length === 0) {
      return [];
    }
    let compact = normalized.replace(/\s+/g, '');
    let candidates = GallerySearchService.candidateTerms();
    let tokens: string[] = [];
    for (let i = 0; i < candidates.length; i++) {
      if (compact.indexOf(candidates[i]) >= 0) {
        GallerySearchService.pushUnique(tokens, candidates[i]);
      }
    }
    let raw = normalized.split(' ');
    for (let i = 0; i < raw.length; i++) {
      let token = raw[i].trim();
      if (token.length > 0 && !GallerySearchService.isStopWord(token)) {
        GallerySearchService.pushUnique(tokens, token);
      }
    }
    GallerySearchService.pushChineseBigrams(compact, tokens);
    if (tokens.length === 0 && normalized.length > 0) {
      tokens.push(normalized);
    }
    return tokens;
  }

  private static normalize(value: string): string {
    if (!value) {
      return '';
    }
    return String(value)
      .toLowerCase()
      .replace(/[，。！？、；：,.!?;:\r\n\t/\\|()[\]{}"'`~@#$%^&*_+=<>-]+/g, ' ')
      .replace(/\s+/g, ' ')
      .trim();
  }

  private static isStopWord(value: string): boolean {
    let words = ['我', '的', '了', '吗', '呢', '啊', '找', '一下', '帮我', '有没有', '哪些', '什么', '图片', '截图'];
    for (let i = 0; i < words.length; i++) {
      if (value === words[i]) {
        return true;
      }
    }
    return false;
  }

  private static candidateTerms(): string[] {
    return [
      '聊天', '待办', '会议', '工作', '项目', '客户', '通知', '截图',
      '账单', '消费', '外卖', '餐饮', '购物', '快递', '售后', '健康',
      '体检', '用药', '运动', '睡眠', '饮食', '医疗', '文档', '合同',
      '笔记', '课程', '作业', '证件', '资料', '发票', '家庭', '朋友',
      '聚会', '亲子', '宠物', '节日', '纪念', '账号', '安全', '配置',
      '报错', '登录', '密码', '订单', '金额', '时间', '地点', '商户',
      '标题', '行程', '交通', '停车'
    ];
  }

  private static pushChineseBigrams(text: string, tokens: string[]): void {
    if (text.length < 2) {
      return;
    }
    for (let i = 0; i < text.length - 1; i++) {
      let token = text.substring(i, i + 2);
      if (!GallerySearchService.isStopWord(token)) {
        GallerySearchService.pushUnique(tokens, token);
      }
    }
  }

  private static reasonText(reasons: string[]): string {
    if (reasons.length === 0) {
      return '内容命中';
    }
    return reasons.slice(0, Math.min(3, reasons.length)).join('、');
  }

  private static pushUnique(items: string[], value: string): void {
    if (value.length === 0) {
      return;
    }
    for (let i = 0; i < items.length; i++) {
      if (items[i] === value) {
        return;
      }
    }
    items.push(value);
  }

  private static recencyBoost(createdAt: number): number {
    let age = new Date().getTime() - createdAt;
    if (age < 0) {
      return 0;
    }
    let day = 24 * 60 * 60 * 1000;
    if (age <= 7 * day) {
      return 3;
    }
    if (age <= 30 * day) {
      return 2;
    }
    if (age <= 90 * day) {
      return 1;
    }
    return 0;
  }
}
