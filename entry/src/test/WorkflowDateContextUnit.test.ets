import { describe, it, expect } from '@ohos/hypium';
import { WorkflowDateContext } from '../main/ets/utils/WorkflowDateContext';

export default function workflowDateContextUnitTest() {
  describe('workflowDateContextUnitTest', () => {
    it('formatsExecutionDatePromptWithChineseWeekday', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 8, 14, 5, 9));

      expect(context.runDate()).assertEqual('2026-06-08');
      expect(context.runTimestamp()).assertEqual('2026年06月08日 14:05:09');
      expect(context.datePrompt()).assertContain('今天的日期是: 2026年06月08日 星期一');
      expect(context.datePrompt()).assertContain('当前本地时间是: 2026年06月08日 14:05:09');
      expect(context.datePrompt()).assertContain('相对时间必须以当前任务执行日期为基准');
      expect(context.datePrompt()).assertContain('写入总结或日志时保留原始表达并用方括号[]补充绝对日期或时间');
      expect(context.datePrompt()).assertContain('无法确定时不要编造');
    });

    it('wrapsPromptWithExecutionDateReferenceAndSectionTitle', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 8, 14, 5, 9));
      let prompt = context.withDatePrompt(' 原始任务 prompt ', '原始任务');
      let emptyPrompt = context.withDatePrompt('', '空问题');

      expect(prompt).assertContain('【任务执行时间参考】');
      expect(prompt).assertContain('【原始任务】');
      expect(prompt).assertContain('今天的日期是: 2026年06月08日 星期一');
      expect(prompt).assertContain('当前本地时间是: 2026年06月08日 14:05:09');
      expect(prompt).assertContain('原始任务 prompt');
      expect(emptyPrompt).assertContain('【任务执行时间参考】');
      expect(emptyPrompt).assertContain('【空问题】');
    });

    it('buildsDeciderTaskWithDateReferenceAsTaskPrefix', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 8, 14, 5, 9));
      let task = context.withDatePromptAsTask(' 收集指定微信用户的今天聊天记录 ');

      expect(task.indexOf('【任务执行时间参考】')).assertEqual(0);
      expect(task.indexOf('今天的日期是: 2026年06月08日 星期一') >= 0).assertTrue();
      expect(task.indexOf('收集指定微信用户的今天聊天记录') > task.indexOf('当前本地时间是: 2026年06月08日 14:05:09')).assertTrue();
      expect(task.indexOf('【Decider 当前任务】') < 0).assertTrue();
    });

    it('normalizesDailyLogRelativeDates', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 8, 14, 5, 9));
      let text = '今天复盘，明天提交，后天确认，明天上午9点沟通，后天下午2点开会，后天晚上8点回访，周末整理，下周一发布，近3天跟进，近一周汇总。';
      let normalized = context.normalizeDailyLogText(text);

      expect(normalized).assertContain('今天[2026年06月08日]');
      expect(normalized).assertContain('明天[2026年06月09日]');
      expect(normalized).assertContain('后天[2026年06月10日]');
      expect(normalized).assertContain('明天上午9点[2026年06月09日09:00]');
      expect(normalized).assertContain('后天下午2点[2026年06月10日14:00]');
      expect(normalized).assertContain('后天晚上8点[2026年06月10日20:00]');
      expect(normalized).assertContain('周末[2026年06月13日-2026年06月14日]');
      expect(normalized).assertContain('下周一[2026年06月15日]');
      expect(normalized).assertContain('近3天[2026年06月06日-2026年06月08日]');
      expect(normalized).assertContain('近一周[2026年06月02日-2026年06月08日]');
    });

    it('normalizesRelativeDatesAcrossMonthAndYearBoundaries', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 11, 31, 10, 0, 0));
      let normalized = context.normalizeDailyLogText('明天提交，后天复盘，近3天跟进，近一周汇总。');

      expect(normalized).assertContain('明天[2027年01月01日]');
      expect(normalized).assertContain('后天[2027年01月02日]');
      expect(normalized).assertContain('近3天[2026年12月29日-2026年12月31日]');
      expect(normalized).assertContain('近一周[2026年12月25日-2026年12月31日]');
    });

    it('normalizesNextMondayFromSundayAsNextDay', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 14, 10, 0, 0));

      expect(context.normalizeDailyLogText('下周一发布')).assertContain('下周一[2026年06月15日]');
    });

    it('normalizesWeekendForCurrentWeekendBoundary', 0, () => {
      let saturdayContext = new WorkflowDateContext(new Date(2026, 5, 13, 10, 0, 0));
      let sundayContext = new WorkflowDateContext(new Date(2026, 5, 14, 10, 0, 0));

      expect(saturdayContext.normalizeDailyLogText('周末整理')).assertContain('周末[2026年06月13日-2026年06月14日]');
      expect(sundayContext.normalizeDailyLogText('周末整理')).assertContain('周末[2026年06月13日-2026年06月14日]');
    });

    it('doesNotDuplicateExistingAbsoluteAnnotations', 0, () => {
      let context = new WorkflowDateContext(new Date(2026, 5, 8, 14, 5, 9));
      let normalized = context.normalizeDailyLogText(
        '今天[2026年06月08日]已经标注，后天下午2点[2026年06月10日14:00]也已经标注，近3天[2026年06月06日-2026年06月08日]已标注，周末[2026年06月13日-2026年06月14日]已标注。'
      );

      expect(normalized).assertEqual(
        '今天[2026年06月08日]已经标注，后天下午2点[2026年06月10日14:00]也已经标注，近3天[2026年06月06日-2026年06月08日]已标注，周末[2026年06月13日-2026年06月14日]已标注。'
      );
    });
  });
}
