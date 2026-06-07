interface JsonRepairContext {
  kind: string;
  state: string;
}

export class WorkflowJsonRepair {
  static normalizeJsonText(raw: string): string {
    let text = raw.trim();
    let block = text.match(/```(?:json)?\s*([\s\S]*?)\s*```/i);
    if (block && block.length > 1) {
      text = block[1].trim();
    }
    text = text.replace(/^```(?:json)?\s*/i, '');
    text = text.replace(/\s*```$/, '');
    text = WorkflowJsonRepair.extractFirstJsonObjectText(text);
    return WorkflowJsonRepair.repairLeadingBrokenObjectQuote(text.trim());
  }

  static repairCandidates(text: string): string[] {
    let candidates: string[] = [];
    let unwrapped = WorkflowJsonRepair.unwrapDuplicateOuterBraces(text);
    WorkflowJsonRepair.addRepairCandidate(candidates, unwrapped, text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(text), text);
    WorkflowJsonRepair.addRepairCandidate(candidates, WorkflowJsonRepair.repairJsonStringContent(unwrapped), text);
    return candidates;
  }

  private static extractFirstJsonObjectText(text: string): string {
    let start = text.indexOf('{');
    if (start < 0) {
      return text;
    }
    let depth = 0;
    let inString = false;
    let escaped = false;
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch === '\\') {
          escaped = true;
        } else if (ch === '"') {
          inString = false;
        }
        continue;
      }

      if (ch === '"') {
        inString = true;
      } else if (ch === '{') {
        depth++;
      } else if (ch === '}') {
        depth--;
        if (depth === 0) {
          return text.substring(start, i + 1);
        }
      }
    }

    let end = text.lastIndexOf('}');
    if (end > start) {
      return text.substring(start, end + 1);
    }
    return text.substring(start);
  }

  private static addRepairCandidate(candidates: string[], candidate: string, original: string): void {
    let normalized = candidate.trim();
    if (normalized.length === 0 || normalized === original.trim()) {
      return;
    }
    if (candidates.indexOf(normalized) < 0) {
      candidates.push(normalized);
    }
  }

  private static unwrapDuplicateOuterBraces(text: string): string {
    let trimmed = text.trim();
    if (trimmed.startsWith('{{') && trimmed.endsWith('}}')) {
      let inner = trimmed.substring(1, trimmed.length - 1).trim();
      if (inner.startsWith('{') && inner.endsWith('}')) {
        return inner;
      }
    }
    return trimmed;
  }

  private static repairJsonStringContent(text: string): string {
    let result = '';
    let inString = false;
    let escaped = false;
    let stringRole = '';
    let contexts: JsonRepairContext[] = [];
    for (let i = 0; i < text.length; i++) {
      let ch = text.charAt(i);
      if (!inString) {
        if (ch === '"') {
          inString = true;
          escaped = false;
          stringRole = WorkflowJsonRepair.jsonStringRole(contexts);
        } else {
          WorkflowJsonRepair.updateContext(contexts, ch);
        }
        result += ch;
        continue;
      }

      if (escaped) {
        result += ch;
        escaped = false;
        continue;
      }

      if (ch === '\\') {
        result += ch;
        escaped = true;
        continue;
      }

      if (ch === '"') {
        if (WorkflowJsonRepair.isJsonStringCloseAt(text, i, stringRole, contexts)) {
          inString = false;
          WorkflowJsonRepair.finishString(contexts, stringRole);
          stringRole = '';
          result += ch;
        } else {
          result += '\\"';
        }
        continue;
      }

      if (ch === '\n') {
        result += '\\n';
        continue;
      }
      if (ch === '\r') {
        continue;
      }
      if (ch === '\t') {
        result += '\\t';
        continue;
      }
      result += ch;
    }
    return result;
  }

  private static updateContext(contexts: JsonRepairContext[], ch: string): void {
    if (ch === '{') {
      contexts.push({ kind: 'object', state: 'keyOrEnd' });
      return;
    }
    if (ch === '[') {
      contexts.push({ kind: 'array', state: 'valueOrEnd' });
      return;
    }
    if (ch === '}' || ch === ']') {
      if (contexts.length > 0) {
        contexts.pop();
      }
      WorkflowJsonRepair.markValueFinished(contexts);
      return;
    }
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top === null) {
      return;
    }
    if (ch === ':' && top.kind === 'object') {
      top.state = 'value';
    } else if (ch === ',') {
      top.state = top.kind === 'object' ? 'keyOrEnd' : 'valueOrEnd';
    }
  }

  private static jsonStringRole(contexts: JsonRepairContext[]): string {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top !== null && top.kind === 'object' && top.state === 'keyOrEnd') {
      return 'key';
    }
    return 'value';
  }

  private static finishString(contexts: JsonRepairContext[], role: string): void {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (role === 'key' && top !== null && top.kind === 'object') {
      top.state = 'colon';
      return;
    }
    WorkflowJsonRepair.markValueFinished(contexts);
  }

  private static markValueFinished(contexts: JsonRepairContext[]): void {
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top !== null) {
      top.state = 'commaOrEnd';
    }
  }

  private static peekContext(contexts: JsonRepairContext[]): JsonRepairContext | null {
    if (contexts.length === 0) {
      return null;
    }
    return contexts[contexts.length - 1];
  }

  private static isJsonStringCloseAt(text: string, quoteIndex: number, role: string,
    contexts: JsonRepairContext[]): boolean {
    let nextIndex = WorkflowJsonRepair.nextNonWhitespaceIndex(text, quoteIndex + 1);
    let next = nextIndex >= 0 ? text.charAt(nextIndex) : '';
    if (role === 'key') {
      return next === ':';
    }
    if (next.length === 0 || next === '}' || next === ']') {
      return true;
    }
    if (next !== ',') {
      return false;
    }
    let top = WorkflowJsonRepair.peekContext(contexts);
    if (top === null || top.kind === 'array') {
      return true;
    }
    return WorkflowJsonRepair.commaStartsNextObjectField(text, nextIndex);
  }

  private static commaStartsNextObjectField(text: string, commaIndex: number): boolean {
    let keyStart = WorkflowJsonRepair.nextNonWhitespaceIndex(text, commaIndex + 1);
    if (keyStart < 0 || text.charAt(keyStart) !== '"') {
      return false;
    }
    let keyEnd = WorkflowJsonRepair.findNextUnescapedQuote(text, keyStart + 1);
    if (keyEnd < 0) {
      return false;
    }
    let afterKey = WorkflowJsonRepair.nextNonWhitespaceIndex(text, keyEnd + 1);
    return afterKey >= 0 && text.charAt(afterKey) === ':';
  }

  private static findNextUnescapedQuote(text: string, start: number): number {
    let escaped = false;
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        return i;
      }
    }
    return -1;
  }

  private static nextNonWhitespaceIndex(text: string, start: number): number {
    for (let i = start; i < text.length; i++) {
      let ch = text.charAt(i);
      if (ch !== ' ' && ch !== '\n' && ch !== '\r' && ch !== '\t') {
        return i;
      }
    }
    return -1;
  }

  private static repairLeadingBrokenObjectQuote(text: string): string {
    return text.replace(/^(\{\s*)"\s*(?="[^"]+"\s*:)/, '$1');
  }
}
