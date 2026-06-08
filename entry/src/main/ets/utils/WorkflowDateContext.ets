export class WorkflowDateContext {
  private readonly startedAt: Date;

  constructor(startedAt: Date) {
    this.startedAt = new Date(startedAt.getTime());
  }

  datePrompt(): string {
    return '今天的日期是: ' + this.formatDateCn(this.startedAt) + ' ' + this.weekdayCn(this.startedAt) + '\n' +
      '当前本地时间是: ' + this.runTimestamp() + '\n' +
      '规则说明：相对时间必须以当前任务执行日期为基准；写入总结或日志时保留原始表达并用方括号[]补充绝对日期或时间；无法确定时不要编造。';
  }

  runDate(): string {
    return this.formatDateIso(this.startedAt);
  }

  runTimestamp(): string {
    return this.formatDateCn(this.startedAt) + ' ' + this.pad2(this.startedAt.getHours()) + ':' +
      this.pad2(this.startedAt.getMinutes()) + ':' + this.pad2(this.startedAt.getSeconds());
  }

  withDatePrompt(prompt: string, sectionTitle: string): string {
    let dateReferenceBlock = '【任务执行时间参考】\n' + this.datePrompt();
    let trimmedPrompt = prompt.trim();
    return dateReferenceBlock + '\n\n【' + sectionTitle + '】\n' + trimmedPrompt;
  }

  withDatePromptAsTask(task: string): string {
    let dateReferenceBlock = '【任务执行时间参考】\n' + this.datePrompt();
    return dateReferenceBlock + '\n\n' + task.trim();
  }

  normalizeDailyLogText(text: string): string {
    let normalized = this.annotateRelativeDateTimePhrases(text);
    let weekendRange = this.weekendRange();
    normalized = this.annotateLiteral(normalized, '近一周', this.formatRangeCn(this.addDays(-6), this.startedAt));
    normalized = this.annotateLiteral(normalized, '近3天', this.formatRangeCn(this.addDays(-2), this.startedAt));
    normalized = this.annotateLiteral(normalized, '下周一', this.formatDateCn(this.nextWeekday(1)));
    normalized = this.annotateLiteral(normalized, '周末', this.formatRangeCn(weekendRange.start, weekendRange.end));
    normalized = this.annotateLiteral(normalized, '后天', this.formatDateCn(this.addDays(2)));
    normalized = this.annotateLiteral(normalized, '明天', this.formatDateCn(this.addDays(1)));
    normalized = this.annotateLiteral(normalized, '今天', this.formatDateCn(this.startedAt));
    return normalized;
  }

  private annotateRelativeDateTimePhrases(text: string): string {
    let normalized = text;
    let days: RelativeDaySpec[] = [
      { literal: '今天', offsetDays: 0 },
      { literal: '明天', offsetDays: 1 },
      { literal: '后天', offsetDays: 2 }
    ];
    let periods: string[] = ['早上', '上午', '中午', '下午', '晚上'];

    for (let dayIndex = 0; dayIndex < days.length; dayIndex++) {
      for (let periodIndex = 0; periodIndex < periods.length; periodIndex++) {
        for (let hour = 0; hour <= 24; hour++) {
          let phrase = days[dayIndex].literal + periods[periodIndex] + hour.toString() + '点';
          let date = this.addDays(days[dayIndex].offsetDays);
          normalized = this.annotateLiteral(normalized, phrase, this.formatDateHourCn(date, this.resolveHour(periods[periodIndex], hour)));
        }
      }
    }
    return normalized;
  }

  private annotateLiteral(text: string, literal: string, annotation: string): string {
    let output = '';
    let searchStart = 0;
    let matchStart = text.indexOf(literal, searchStart);
    while (matchStart >= 0) {
      let matchEnd = matchStart + literal.length;
      output += text.substring(searchStart, matchEnd);
      if (!this.hasImmediateAnnotation(text, matchEnd) && !this.isFollowedByRelativeTimePhrase(literal, text, matchEnd)) {
        output += '[' + annotation + ']';
      }
      searchStart = matchEnd;
      matchStart = text.indexOf(literal, searchStart);
    }
    output += text.substring(searchStart);
    return output;
  }

  private hasImmediateAnnotation(text: string, startIndex: number): boolean {
    return text.substring(startIndex, startIndex + 1) === '[';
  }

  private isFollowedByRelativeTimePhrase(literal: string, text: string, matchEnd: number): boolean {
    if (literal !== '今天' && literal !== '明天' && literal !== '后天') {
      return false;
    }
    let periods: string[] = ['早上', '上午', '中午', '下午', '晚上'];
    for (let periodIndex = 0; periodIndex < periods.length; periodIndex++) {
      for (let hour = 0; hour <= 24; hour++) {
        let suffix = periods[periodIndex] + hour.toString() + '点';
        if (text.substring(matchEnd, matchEnd + suffix.length) === suffix) {
          return true;
        }
      }
    }
    return false;
  }

  private addDays(days: number): Date {
    let date = new Date(this.startedAt.getTime());
    date.setDate(date.getDate() + days);
    return date;
  }

  private nextWeekday(day: number): Date {
    let current = this.startedAt.getDay();
    let offset = day - current;
    if (offset <= 0) {
      offset += 7;
    }
    return this.addDays(offset);
  }

  private weekendRange(): WeekendRange {
    let current = this.startedAt.getDay();
    if (current === 6) {
      return { start: this.startedAt, end: this.addDays(1) };
    }
    if (current === 0) {
      return { start: this.addDays(-1), end: this.startedAt };
    }
    let saturdayOffset = 6 - current;
    return { start: this.addDays(saturdayOffset), end: this.addDays(saturdayOffset + 1) };
  }

  private formatRangeCn(start: Date, end: Date): string {
    return this.formatDateCn(start) + '-' + this.formatDateCn(end);
  }

  private formatDateIso(date: Date): string {
    return date.getFullYear().toString() + '-' + this.pad2(date.getMonth() + 1) + '-' + this.pad2(date.getDate());
  }

  private formatDateCn(date: Date): string {
    return date.getFullYear().toString() + '年' + this.pad2(date.getMonth() + 1) + '月' + this.pad2(date.getDate()) + '日';
  }

  private formatDateHourCn(date: Date, hour: number): string {
    return this.formatDateCn(date) + this.pad2(hour) + ':00';
  }

  private resolveHour(period: string, hour: number): number {
    if ((period === '下午' || period === '晚上') && hour < 12) {
      return hour + 12;
    }
    if (period === '中午' && hour > 0 && hour < 11) {
      return hour + 12;
    }
    return hour;
  }

  private weekdayCn(date: Date): string {
    let weekdays: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];
    return weekdays[date.getDay()];
  }

  private pad2(value: number): string {
    if (value < 10) {
      return '0' + value.toString();
    }
    return value.toString();
  }
}

interface WeekendRange {
  start: Date;
  end: Date;
}

interface RelativeDaySpec {
  literal: string;
  offsetDays: number;
}
