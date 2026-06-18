export type MarkdownBlockType = 'heading' | 'paragraph' | 'list' | 'quote' | 'code' | 'table' | 'divider';
export type MarkdownInlineType = 'text' | 'strong' | 'code' | 'link';

export interface MarkdownParseOptions {
  maxBlocks?: number;
}

export interface MarkdownInline {
  type: MarkdownInlineType;
  text: string;
  href: string;
}

export interface MarkdownListItem {
  text: string;
  inlines: MarkdownInline[];
  marker: string;
}

export interface MarkdownBlock {
  type: MarkdownBlockType;
  text: string;
  inlines: MarkdownInline[];
  level: number;
  ordered: boolean;
  items: MarkdownListItem[];
  language: string;
  headers: string[];
  rows: string[][];
}

interface ListLine {
  matched: boolean;
  ordered: boolean;
  text: string;
  marker: string;
}

// 统一 Markdown 预览只做轻量语法识别，不回写、不清洗原文件内容，避免影响 daily-log、导出和模型上下文。
// 解析顺序按 Markdown 中更“强”的块优先：代码块、标题、分割线、表格、列表、引用，最后才归并普通段落。
export function parseMarkdown(text: string, options?: MarkdownParseOptions): MarkdownBlock[] {
  let source = stripIgnorableMetadata(text);
  let lines = source.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  let blocks: MarkdownBlock[] = [];
  let index = 0;
  let maxBlocks = options !== undefined && options.maxBlocks !== undefined ? options.maxBlocks : 0;

  while (index < lines.length) {
    if (maxBlocks > 0 && blocks.length >= maxBlocks) {
      break;
    }

    let line = lines[index];
    let trimmed = line.trim();
    if (trimmed.length === 0) {
      index++;
      continue;
    }

    if (isFenceStart(trimmed)) {
      let parsedCode = parseCodeBlock(lines, index);
      blocks.push(createCodeBlock(parsedCode.text, parsedCode.language));
      index = parsedCode.nextIndex;
      continue;
    }

    let headingLevel = headingMarkerLevel(trimmed);
    if (headingLevel > 0) {
      let headingText = stripHeadingMarker(trimmed, headingLevel);
      blocks.push(createTextBlock('heading', headingText, headingLevel));
      index++;
      continue;
    }

    if (isDividerLine(trimmed)) {
      blocks.push(createDividerBlock());
      index++;
      continue;
    }

    if (isTableStart(lines, index)) {
      let parsedTable = parseTableBlock(lines, index);
      blocks.push(createTableBlock(parsedTable.headers, parsedTable.rows));
      index = parsedTable.nextIndex;
      continue;
    }

    let listLine = parseListLine(line);
    if (listLine.matched) {
      let parsedList = parseListBlock(lines, index, listLine.ordered);
      blocks.push(createListBlock(parsedList.items, listLine.ordered));
      index = parsedList.nextIndex;
      continue;
    }

    if (trimmed.startsWith('>')) {
      let parsedQuote = parseQuoteBlock(lines, index);
      blocks.push(createTextBlock('quote', parsedQuote.text, 0));
      index = parsedQuote.nextIndex;
      continue;
    }

    let parsedParagraph = parseParagraphBlock(lines, index);
    blocks.push(createTextBlock('paragraph', parsedParagraph.text, 0));
    index = parsedParagraph.nextIndex;
  }

  return blocks;
}

export function markdownToPlainText(text: string): string {
  let blocks = parseMarkdown(text);
  let parts: string[] = [];
  for (let i = 0; i < blocks.length; i++) {
    appendBlockPlainText(parts, blocks[i]);
  }
  return normalizePlainText(parts.join('\n'));
}

// 标题提取用于聊天折叠标题、采集事件标题等一行摘要场景，只读取第一个有效块的纯文本。
export function markdownTitleText(text: string): string {
  let blocks = parseMarkdown(text, { maxBlocks: 8 });
  for (let i = 0; i < blocks.length; i++) {
    let block = blocks[i];
    if (block.type === 'divider') {
      continue;
    }
    if (block.type === 'list' && block.items.length > 0) {
      return normalizePlainText(block.items[0].text);
    }
    if (block.type === 'table' && block.headers.length > 0) {
      return normalizePlainText(block.headers.join(' '));
    }
    let value = normalizePlainText(blockTextPlain(block));
    if (value.length > 0) {
      return value;
    }
  }
  return '';
}

function createTextBlock(type: MarkdownBlockType, text: string, level: number): MarkdownBlock {
  let inlines = parseMarkdownInlines(text);
  let plain = inlinePlainText(inlines);
  return {
    type: type,
    text: plain,
    inlines: inlines,
    level: level,
    ordered: false,
    items: [],
    language: '',
    headers: [],
    rows: []
  };
}

function createListBlock(items: MarkdownListItem[], ordered: boolean): MarkdownBlock {
  let texts: string[] = [];
  for (let i = 0; i < items.length; i++) {
    texts.push(items[i].text);
  }
  return {
    type: 'list',
    text: texts.join('\n'),
    inlines: [],
    level: 0,
    ordered: ordered,
    items: items,
    language: '',
    headers: [],
    rows: []
  };
}

function createCodeBlock(text: string, language: string): MarkdownBlock {
  return {
    type: 'code',
    text: text,
    inlines: [],
    level: 0,
    ordered: false,
    items: [],
    language: language,
    headers: [],
    rows: []
  };
}

function createTableBlock(headers: string[], rows: string[][]): MarkdownBlock {
  return {
    type: 'table',
    text: headers.join(' '),
    inlines: [],
    level: 0,
    ordered: false,
    items: [],
    language: '',
    headers: headers,
    rows: rows
  };
}

function createDividerBlock(): MarkdownBlock {
  return {
    type: 'divider',
    text: '',
    inlines: [],
    level: 0,
    ordered: false,
    items: [],
    language: '',
    headers: [],
    rows: []
  };
}

interface ParsedTextBlock {
  text: string;
  nextIndex: number;
}

interface ParsedCodeBlock {
  text: string;
  language: string;
  nextIndex: number;
}

interface ParsedListBlock {
  items: MarkdownListItem[];
  nextIndex: number;
}

interface ParsedTableBlock {
  headers: string[];
  rows: string[][];
  nextIndex: number;
}

function parseCodeBlock(lines: string[], startIndex: number): ParsedCodeBlock {
  let fence = lines[startIndex].trim();
  let marker = fence.startsWith('~~~') ? '~~~' : '```';
  let language = fence.substring(marker.length).trim();
  let content: string[] = [];
  let index = startIndex + 1;
  while (index < lines.length) {
    if (lines[index].trim().startsWith(marker)) {
      return { text: content.join('\n'), language: language, nextIndex: index + 1 };
    }
    content.push(lines[index]);
    index++;
  }
  return { text: content.join('\n'), language: language, nextIndex: index };
}

function parseListBlock(lines: string[], startIndex: number, ordered: boolean): ParsedListBlock {
  let items: MarkdownListItem[] = [];
  let index = startIndex;
  while (index < lines.length) {
    let parsed = parseListLine(lines[index]);
    if (!parsed.matched || parsed.ordered !== ordered) {
      break;
    }
    let itemSourceText = normalizeListItemMarkdownText(parsed.text);
    let itemText = inlinePlainText(parseMarkdownInlines(itemSourceText));
    items.push({ text: itemText, inlines: parseMarkdownInlines(itemSourceText), marker: parsed.marker });
    index++;
  }
  return { items: items, nextIndex: index };
}

function normalizeListItemMarkdownText(text: string): string {
  let trimmed = text.trim();
  let headingLevel = headingMarkerLevel(trimmed);
  if (headingLevel > 0) {
    return stripHeadingMarker(trimmed, headingLevel);
  }
  return trimmed;
}

function parseQuoteBlock(lines: string[], startIndex: number): ParsedTextBlock {
  let parts: string[] = [];
  let index = startIndex;
  while (index < lines.length) {
    let trimmed = lines[index].trim();
    if (!trimmed.startsWith('>')) {
      break;
    }
    parts.push(trimmed.substring(1).trim());
    index++;
  }
  return { text: parts.join('\n'), nextIndex: index };
}

function parseParagraphBlock(lines: string[], startIndex: number): ParsedTextBlock {
  let parts: string[] = [];
  let index = startIndex;
  while (index < lines.length) {
    let line = lines[index];
    let trimmed = line.trim();
    if (trimmed.length === 0 || isFenceStart(trimmed) || headingMarkerLevel(trimmed) > 0 ||
      isDividerLine(trimmed) || parseListLine(line).matched || trimmed.startsWith('>') || isTableStart(lines, index)) {
      break;
    }
    parts.push(trimmed);
    index++;
  }
  return { text: parts.join(' '), nextIndex: index };
}

function parseTableBlock(lines: string[], startIndex: number): ParsedTableBlock {
  let headers = splitTableRow(lines[startIndex]);
  let rows: string[][] = [];
  let index = startIndex + 2;
  while (index < lines.length) {
    let trimmed = lines[index].trim();
    if (trimmed.length === 0 || trimmed.indexOf('|') < 0 || isDividerLine(trimmed)) {
      break;
    }
    rows.push(splitTableRow(lines[index]));
    index++;
  }
  return { headers: headers, rows: rows, nextIndex: index };
}

function isTableStart(lines: string[], index: number): boolean {
  if (index + 1 >= lines.length) {
    return false;
  }
  let header = lines[index].trim();
  let separator = lines[index + 1].trim();
  return header.indexOf('|') >= 0 && isTableSeparator(separator);
}

function splitTableRow(line: string): string[] {
  let trimmed = line.trim();
  if (trimmed.startsWith('|')) {
    trimmed = trimmed.substring(1);
  }
  if (trimmed.endsWith('|')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  let rawCells = trimmed.split('|');
  let cells: string[] = [];
  for (let i = 0; i < rawCells.length; i++) {
    cells.push(inlinePlainText(parseMarkdownInlines(rawCells[i].trim())));
  }
  return cells;
}

function isTableSeparator(line: string): boolean {
  if (line.indexOf('|') < 0) {
    return false;
  }
  let cells = splitRawTableCells(line);
  if (cells.length === 0) {
    return false;
  }
  for (let i = 0; i < cells.length; i++) {
    if (!isSeparatorCell(cells[i])) {
      return false;
    }
  }
  return true;
}

function splitRawTableCells(line: string): string[] {
  let trimmed = line.trim();
  if (trimmed.startsWith('|')) {
    trimmed = trimmed.substring(1);
  }
  if (trimmed.endsWith('|')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  let rawCells = trimmed.split('|');
  let cells: string[] = [];
  for (let i = 0; i < rawCells.length; i++) {
    let cell = rawCells[i].trim();
    if (cell.length > 0) {
      cells.push(cell);
    }
  }
  return cells;
}

function isSeparatorCell(cell: string): boolean {
  let hyphenCount = 0;
  for (let i = 0; i < cell.length; i++) {
    let ch = cell.charAt(i);
    if (ch === '-') {
      hyphenCount++;
    } else if (ch !== ':' && ch !== ' ') {
      return false;
    }
  }
  return hyphenCount >= 3;
}

function parseListLine(line: string): ListLine {
  let trimmed = line.trim();
  if (trimmed.length >= 2) {
    let marker = trimmed.charAt(0);
    if ((marker === '-' || marker === '*' || marker === '+') && trimmed.charAt(1) === ' ') {
      return { matched: true, ordered: false, text: trimmed.substring(2).trim(), marker: marker };
    }
  }

  let dotIndex = trimmed.indexOf('.');
  let parenIndex = trimmed.indexOf(')');
  let markerIndex = dotIndex >= 0 && (parenIndex < 0 || dotIndex < parenIndex) ? dotIndex : parenIndex;
  if (markerIndex > 0 && markerIndex < 5 && markerIndex + 1 < trimmed.length && trimmed.charAt(markerIndex + 1) === ' ') {
    let numberText = trimmed.substring(0, markerIndex);
    if (isDigits(numberText)) {
      return {
        matched: true,
        ordered: true,
        text: trimmed.substring(markerIndex + 2).trim(),
        marker: numberText + trimmed.charAt(markerIndex)
      };
    }
  }

  return { matched: false, ordered: false, text: '', marker: '' };
}

function isDigits(text: string): boolean {
  if (text.length === 0) {
    return false;
  }
  for (let i = 0; i < text.length; i++) {
    let code = text.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

function isFenceStart(line: string): boolean {
  return line.startsWith('```') || line.startsWith('~~~');
}

function headingMarkerLevel(line: string): number {
  let level = 0;
  while (level < line.length && level < 6 && line.charAt(level) === '#') {
    level++;
  }
  if (level === 0 || level >= line.length || line.charAt(level) !== ' ') {
    return 0;
  }
  return level;
}

function stripHeadingMarker(line: string, level: number): string {
  let text = line.substring(level).trim();
  while (text.endsWith('#')) {
    text = text.substring(0, text.length - 1).trim();
  }
  return text;
}

function isDividerLine(line: string): boolean {
  let compact = line.split(' ').join('');
  if (compact.length < 3) {
    return false;
  }
  let first = compact.charAt(0);
  if (first !== '-' && first !== '*' && first !== '_') {
    return false;
  }
  for (let i = 1; i < compact.length; i++) {
    if (compact.charAt(i) !== first) {
      return false;
    }
  }
  return true;
}

export function parseMarkdownInlines(text: string): MarkdownInline[] {
  // 行内解析只保留可显示文本：链接不暴露 URL，代码/加粗只作为渲染 hint，避免把 Markdown 标记带进纯文本。
  let inlines: MarkdownInline[] = [];
  let index = 0;
  while (index < text.length) {
    if (text.startsWith('**', index)) {
      let end = text.indexOf('**', index + 2);
      if (end > index + 2) {
        inlines.push({ type: 'strong', text: text.substring(index + 2, end), href: '' });
        index = end + 2;
        continue;
      }
    }
    if (text.charAt(index) === '`') {
      let end = text.indexOf('`', index + 1);
      if (end > index + 1) {
        inlines.push({ type: 'code', text: text.substring(index + 1, end), href: '' });
        index = end + 1;
        continue;
      }
    }
    if (text.charAt(index) === '[') {
      let closeLabel = text.indexOf(']', index + 1);
      if (closeLabel > index + 1 && closeLabel + 1 < text.length && text.charAt(closeLabel + 1) === '(') {
        let closeHref = text.indexOf(')', closeLabel + 2);
        if (closeHref > closeLabel + 2) {
          let label = text.substring(index + 1, closeLabel);
          let href = text.substring(closeLabel + 2, closeHref).trim();
          inlines.push({ type: 'link', text: inlinePlainText(parseMarkdownInlines(label)), href: href });
          index = closeHref + 1;
          continue;
        }
      }
    }

    let next = nextInlineMarkerIndex(text, index + 1);
    inlines.push({ type: 'text', text: text.substring(index, next), href: '' });
    index = next;
  }
  return mergeTextInlines(inlines);
}

function nextInlineMarkerIndex(text: string, start: number): number {
  let next = text.length;
  let strong = text.indexOf('**', start);
  let code = text.indexOf('`', start);
  let link = text.indexOf('[', start);
  if (strong >= 0 && strong < next) {
    next = strong;
  }
  if (code >= 0 && code < next) {
    next = code;
  }
  if (link >= 0 && link < next) {
    next = link;
  }
  return next;
}

function mergeTextInlines(inlines: MarkdownInline[]): MarkdownInline[] {
  let merged: MarkdownInline[] = [];
  for (let i = 0; i < inlines.length; i++) {
    let current = inlines[i];
    if (current.text.length === 0) {
      continue;
    }
    if (merged.length > 0 && current.type === 'text' && merged[merged.length - 1].type === 'text') {
      let previous = merged[merged.length - 1];
      merged[merged.length - 1] = { type: 'text', text: previous.text + current.text, href: '' };
    } else {
      merged.push(current);
    }
  }
  return merged;
}

function inlinePlainText(inlines: MarkdownInline[]): string {
  let parts: string[] = [];
  for (let i = 0; i < inlines.length; i++) {
    parts.push(inlines[i].text);
  }
  return normalizePlainText(parts.join(''));
}

function appendBlockPlainText(parts: string[], block: MarkdownBlock): void {
  if (block.type === 'divider') {
    return;
  }
  if (block.type === 'list') {
    for (let i = 0; i < block.items.length; i++) {
      parts.push(block.items[i].text);
    }
    return;
  }
  if (block.type === 'table') {
    if (block.headers.length > 0) {
      parts.push(block.headers.join(' '));
    }
    for (let i = 0; i < block.rows.length; i++) {
      parts.push(block.rows[i].join(' '));
    }
    return;
  }
  parts.push(blockTextPlain(block));
}

function blockTextPlain(block: MarkdownBlock): string {
  if (block.inlines.length > 0) {
    return inlinePlainText(block.inlines);
  }
  return block.text;
}

function normalizePlainText(text: string): string {
  return text.replace(/[ \t]+/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
}

function stripIgnorableMetadata(text: string): string {
  // 前置 YAML metadata 和 HTML 注释常由采集/日志生成链路写入，预览与标题提取时忽略，但原文仍保留在存储中。
  let normalized = text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  let lines = normalized.split('\n');
  let start = 0;
  if (lines.length > 1 && lines[0].trim() === '---') {
    for (let i = 1; i < lines.length; i++) {
      if (lines[i].trim() === '---') {
        start = i + 1;
        break;
      }
    }
  }
  return restoreFlattenedMarkdownBreaks(stripLeadingMetadataComments(lines.slice(start).join('\n')));
}

function stripLeadingMetadataComments(text: string): string {
  let remaining = text;
  while (remaining.trimStart().startsWith('<!--')) {
    let leadingWhitespace = remaining.length - remaining.trimStart().length;
    let start = leadingWhitespace;
    let end = remaining.indexOf('-->', start + 4);
    if (end < 0) {
      return remaining;
    }
    let comment = remaining.substring(start + 4, end);
    if (!isMetadataComment(comment)) {
      return remaining;
    }
    remaining = remaining.substring(0, leadingWhitespace) + remaining.substring(end + 3);
  }
  return remaining;
}

function isMetadataComment(comment: string): boolean {
  let text = comment.trim();
  return text.startsWith('DAILY_LOG_METADATA') || text.indexOf('"workflow_metadata"') >= 0 ||
    text.indexOf('latest_entry_index') >= 0;
}

function restoreFlattenedMarkdownBreaks(text: string): string {
  // 数据汇总层会把部分 normalized_fact 压成单行，导致 "## 标题 - 列表 ### 小标题" 在详情页仍像源码。
  // 这里仅在明显存在 Markdown 结构标记时恢复展示换行，不参与索引、存储或导出。
  if (text.indexOf('\n') >= 0) {
    return text;
  }
  let trimmed = text.trim();
  if (!looksLikeFlattenedMarkdown(trimmed)) {
    return text;
  }
  let restored = trimmed.replace(/\s+(#{1,6}\s+)/g, '\n$1');
  if (shouldRestoreFlattenedListBreaks(trimmed)) {
    restored = restored.replace(/\s+([-*+]\s+)/g, '\n$1');
  }
  return restored;
}

function looksLikeFlattenedMarkdown(text: string): boolean {
  if (headingMarkerLevel(text) > 0) {
    return true;
  }
  return text.indexOf(' ### ') >= 0 || text.indexOf(' ## ') >= 0;
}

function shouldRestoreFlattenedListBreaks(text: string): boolean {
  return text.indexOf(' ### ') >= 0 || text.indexOf(' ## ') >= 0 || countMarkerOccurrences(text, ' - ') >= 2 ||
    countMarkerOccurrences(text, ' * ') >= 2 || countMarkerOccurrences(text, ' + ') >= 2;
}

function countMarkerOccurrences(text: string, marker: string): number {
  let count = 0;
  let index = text.indexOf(marker);
  while (index >= 0) {
    count++;
    index = text.indexOf(marker, index + marker.length);
  }
  return count;
}
