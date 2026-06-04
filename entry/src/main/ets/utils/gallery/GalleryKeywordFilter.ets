export interface GalleryKeywordMatch {
  matched: boolean;
  keywords: string[];
}

const USEFUL_KEYWORDS: string[] = [
  '检验', '体检', '化验', '检查', '诊断', '病理', '报告',
  '医院', '患者', '门诊', '住院', '科室', '病历', '挂号',
  '血常规', '尿常规', '生化', '肝功', '肾功', '血糖', '血脂', '血压',
  '白细胞', '红细胞', '血红蛋白', '血小板', '转氨酶', '胆固醇', '尿酸',
  'CT', 'MRI', 'B超', '心电图', 'X光', '超声', '彩超', '核磁',
  '异常', '偏高', '偏低', '阳性', '阴性', '正常',
  '医生', '护士', '药', 'mg', 'mmol', '单位', '指标',
  '微信', '微信支付', '联系人', '聊天记录', '群聊',
  '消息', '未读', '语音', '朋友圈', '公众号', '小程序',
  '短信', '验证码', '通知短信', '服务提醒', '发送时间', '对方',
  '淘宝', '天猫', '京东', '拼多多', '闲鱼', '抖音商城', '小红书',
  '订单', '订单号', '商品', '店铺', '客服', '买家', '卖家',
  '待付款', '待发货', '待收货', '待评价', '已完成', '已取消',
  '物流', '快递', '运单', '包裹', '签收', '派送', '已揽收', '运输中',
  '退款', '退货', '售后', '实付款', '合计', '优惠', '满减',
  '收货地址', '预计送达', '立即支付', '查看物流', '确认收货', '支付',
  '高铁', '火车', '机票', '航班', '登机', '值机', '车次', '座位',
  '打车', '出租车', '网约车', '滴滴', '顺风车', '目的地', '司机已接单',
  '酒店', '民宿', '入住', '离店', '房间', '订单详情', '预订成功',
  '出发地', '行程', '乘客', '票价', '车票', '酒店确认',
  '美团', '饿了么', '外卖', '堂食', '优惠券', '商家', '下单成功',
  '配送中', '骑手', '送达', '菜品', '餐品', '总价', '已支付',
  '账单', '缴费', '余额', '支付成功', '待支付', '发票', '备注',
  '日程', '待办', '提醒', '会议', '事项', '日历', '任务',
  '时间', '日期', '地点', '电话', '地址'
];

export class GalleryKeywordFilter {
  static matchUsefulKeywords(ocrText: string): GalleryKeywordMatch {
    let text = ocrText ? ocrText : '';
    let tokens = GalleryKeywordFilter.extractTokens(text);
    let matched: string[] = [];
    for (let i = 0; i < USEFUL_KEYWORDS.length; i++) {
      let keyword = USEFUL_KEYWORDS[i];
      if (GalleryKeywordFilter.containsIgnoreCase(text, keyword) ||
        GalleryKeywordFilter.tokenMatchesKeyword(tokens, keyword)) {
        GalleryKeywordFilter.pushUnique(matched, keyword);
      }
    }
    return {
      matched: matched.length > 0,
      keywords: matched
    };
  }

  private static extractTokens(text: string): string[] {
    let normalized = text.replace(/[^\u4e00-\u9fffA-Za-z0-9_]+/g, ' ');
    let pieces = normalized.split(' ');
    let tokens: string[] = [];
    for (let i = 0; i < pieces.length; i++) {
      let value = pieces[i].trim();
      if (value.length > 0) {
        tokens.push(value);
      }
    }
    return tokens;
  }

  private static tokenMatchesKeyword(tokens: string[], keyword: string): boolean {
    for (let i = 0; i < tokens.length; i++) {
      if (tokens[i].length > 0 && GalleryKeywordFilter.containsIgnoreCase(keyword, tokens[i])) {
        return true;
      }
    }
    return false;
  }

  private static containsIgnoreCase(text: string, part: string): boolean {
    return text.toLowerCase().indexOf(part.toLowerCase()) >= 0;
  }

  private static pushUnique(items: string[], value: string): void {
    for (let i = 0; i < items.length; i++) {
      if (items[i] === value) {
        return;
      }
    }
    items.push(value);
  }
}
