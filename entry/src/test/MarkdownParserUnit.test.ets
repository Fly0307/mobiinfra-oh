import { describe, it, expect } from '@ohos/hypium';
import {
  markdownTitleText,
  markdownToPlainText,
  parseMarkdown,
  MarkdownBlock
} from '../main/ets/utils/markdown/MarkdownParser';

function findBlock(blocks: MarkdownBlock[], type: string): MarkdownBlock | null {
  for (let i = 0; i < blocks.length; i++) {
    if (blocks[i].type === type) {
      return blocks[i];
    }
  }
  return null;
}

export default function markdownParserUnitTest() {
  describe('markdownParserUnitTest', () => {
    it('parsesWechatCollectionMarkdownIntoReadableBlocks', 0, () => {
      let markdown = '---\nsource: wechat\n---\n<!-- DAILY_LOG_METADATA\n{"workflow_metadata":{}}\n-->\n## 小赵\n' +
        '- 19:01 你好\n- 19:02 明天见\n\n### 完整消息摘录\n无消息文本';

      let blocks: MarkdownBlock[] = parseMarkdown(markdown);
      let plain: string = markdownToPlainText(markdown);

      expect(blocks[0].type).assertEqual('heading');
      expect(blocks[0].text).assertEqual('小赵');
      expect(blocks[0].level).assertEqual(2);
      expect(findBlock(blocks, 'list') !== null).assertTrue();
      expect(plain.indexOf('source: wechat')).assertEqual(-1);
      expect(plain.indexOf('DAILY_LOG_METADATA')).assertEqual(-1);
      expect(plain.indexOf('##')).assertEqual(-1);
      expect(plain.indexOf('###')).assertEqual(-1);
      expect(plain.indexOf('无消息文本') >= 0).assertTrue();
    });

    it('parsesChatMarkdownWithoutLeakingMarkersInPlainText', 0, () => {
      let markdown = '**重点** 段落包含 `inline code` 和 [官网](https://example.com)。\n\n' +
        '```json\n{"ok":true}\n```\n\n普通段落';

      let blocks: MarkdownBlock[] = parseMarkdown(markdown);
      let plain: string = markdownToPlainText(markdown);

      expect(findBlock(blocks, 'code') !== null).assertTrue();
      expect(plain.indexOf('重点') >= 0).assertTrue();
      expect(plain.indexOf('inline code') >= 0).assertTrue();
      expect(plain.indexOf('官网') >= 0).assertTrue();
      expect(plain.indexOf('https://example.com')).assertEqual(-1);
      expect(plain.indexOf('**')).assertEqual(-1);
      expect(plain.indexOf('`')).assertEqual(-1);
      expect(markdownToPlainText('普通无 Markdown 文本')).assertEqual('普通无 Markdown 文本');
    });

    it('parsesPipeTableAndHorizontalRule', 0, () => {
      let markdown = '| 时间 | 内容 |\n| --- | --- |\n| 19:01 | 你好 |\n\n---\n收尾';
      let blocks: MarkdownBlock[] = parseMarkdown(markdown);
      let table: MarkdownBlock | null = findBlock(blocks, 'table');
      let rule: MarkdownBlock | null = findBlock(blocks, 'divider');
      let plain: string = markdownToPlainText(markdown);

      expect(table !== null).assertTrue();
      if (table !== null) {
        expect(table.headers.length).assertEqual(2);
        expect(table.rows.length).assertEqual(1);
        expect(table.rows[0][1]).assertEqual('你好');
      }
      expect(rule !== null).assertTrue();
      expect(plain.indexOf('|')).assertEqual(-1);
      expect(plain.indexOf('时间 内容') >= 0).assertTrue();
      expect(plain.indexOf('收尾') >= 0).assertTrue();
    });

    it('extractsTitleTextFromMarkdownContent', 0, () => {
      expect(markdownTitleText('<!-- DAILY_LOG_METADATA\n{}\n-->\n# **任务结果**\n正文')).assertEqual('任务结果');
      expect(markdownTitleText('- **第一步**：打开应用\n- 第二步')).assertEqual('第一步：打开应用');
      expect(markdownTitleText('普通无 Markdown 文本')).assertEqual('普通无 Markdown 文本');
    });

    it('recoversFlattenedDailyLogMarkdownForDisplay', 0, () => {
      let flattened = '## 微信联系人「大虎」当前可见页面消息采集 - 采集范围：请求最近 1 天，未展开历史 ' +
        '- 联系人：大虎 - 消息数：0 ### 完整消息摘录 （无消息）';
      let plain: string = markdownToPlainText(flattened);

      expect(markdownTitleText(flattened)).assertEqual('微信联系人「大虎」当前可见页面消息采集');
      expect(plain.indexOf('##')).assertEqual(-1);
      expect(plain.indexOf('###')).assertEqual(-1);
      expect(plain.indexOf('采集范围：请求最近 1 天，未展开历史') >= 0).assertTrue();
      expect(plain.indexOf('完整消息摘录') >= 0).assertTrue();
    });

    it('keepsPlainHyphenTextAsOneParagraph', 0, () => {
      let text = '版本 1.0 - 修复崩溃';
      let blocks: MarkdownBlock[] = parseMarkdown(text);

      expect(markdownTitleText(text)).assertEqual(text);
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual('paragraph');
      expect(blocks[0].text).assertEqual(text);
    });

    it('keepsSingleHyphenInsideHeadingText', 0, () => {
      let markdown = '## 版本 1.0 - 修复崩溃';
      let blocks: MarkdownBlock[] = parseMarkdown(markdown);

      expect(markdownTitleText(markdown)).assertEqual('版本 1.0 - 修复崩溃');
      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual('heading');
      expect(blocks[0].text).assertEqual('版本 1.0 - 修复崩溃');
    });

    it('keepsOrderedDailyLogNumbersAndStripsItemHeadings', 0, () => {
      let markdown = '1. ## 小赵提醒下午三点开会\n\n2. ## 大虎无消息';
      let blocks: MarkdownBlock[] = parseMarkdown(markdown);

      expect(blocks.length).assertEqual(2);
      expect(blocks[0].type).assertEqual('list');
      expect(blocks[0].items[0].marker).assertEqual('1.');
      expect(blocks[0].items[0].text).assertEqual('小赵提醒下午三点开会');
      expect(blocks[1].items[0].marker).assertEqual('2.');
      expect(blocks[1].items[0].text).assertEqual('大虎无消息');
    });

    it('keepsHtmlCommentTextInsideCodeBlocks', 0, () => {
      let markdown = '```html\n<!-- keep this example -->\n<div>ok</div>\n```';
      let blocks: MarkdownBlock[] = parseMarkdown(markdown);

      expect(blocks.length).assertEqual(1);
      expect(blocks[0].type).assertEqual('code');
      expect(blocks[0].text.indexOf('<!-- keep this example -->') >= 0).assertTrue();
    });
  });
}
