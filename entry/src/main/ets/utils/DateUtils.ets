const WEEKDAY_LABELS: string[] = ['星期日', '星期一', '星期二', '星期三', '星期四', '星期五', '星期六'];

export interface LocalWeekRange {
  startDate: string;
  endDate: string;
}

export function padDatePart(value: number): string {
  return value < 10 ? '0' + String(value) : String(value);
}

export function formatLocalDateKey(date: Date): string {
  return `${date.getFullYear()}-${padDatePart(date.getMonth() + 1)}-${padDatePart(date.getDate())}`;
}

export function currentLocalDateKey(): string {
  return formatLocalDateKey(new Date());
}

export function localWeekdayLabel(date: Date): string {
  let weekday = date.getDay();
  if (weekday < 0 || weekday >= WEEKDAY_LABELS.length) {
    return '';
  }
  return WEEKDAY_LABELS[weekday];
}

export function weekdayLabelFromDate(value: string): string {
  let date = parseIsoDate(value);
  return date === null ? '' : localWeekdayLabel(date);
}

export function offsetLocalDate(date: Date, days: number): Date {
  let result = new Date(date.getTime());
  result.setDate(result.getDate() + days);
  return result;
}

export function weekRangeFromDate(date: Date): LocalWeekRange {
  let weekday = date.getDay();
  let startOffset = weekday === 0 ? -6 : 1 - weekday;
  let endOffset = weekday === 0 ? 0 : 7 - weekday;
  return {
    startDate: formatLocalDateKey(offsetLocalDate(date, startOffset)),
    endDate: formatLocalDateKey(offsetLocalDate(date, endOffset))
  };
}

export function weekRangeTextFromDate(date: Date): string {
  let range = weekRangeFromDate(date);
  return range.startDate + ' 至 ' + range.endDate;
}

function parseIsoDate(value: string): Date | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    return null;
  }
  let year = Number(value.substring(0, 4));
  let month = Number(value.substring(5, 7));
  let day = Number(value.substring(8, 10));
  let date = new Date(year, month - 1, day);
  if (isNaN(date.getTime()) || date.getFullYear() !== year || date.getMonth() !== month - 1 ||
    date.getDate() !== day) {
    return null;
  }
  return date;
}
