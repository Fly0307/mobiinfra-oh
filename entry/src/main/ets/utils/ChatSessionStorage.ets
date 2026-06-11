import fs from '@ohos.file.fs';
import { parseJsonCompat, stringifyJsonCompat } from './JsonCompat';
import { decodeUtf8Compat, encodeUtf8Compat } from './TextEncodingCompat';
import {
  ChatMessage,
  ChatSessionIndex,
  ChatSessionRecord,
  ChatSessionSummary,
  buildChatSessionSummary,
  createEmptyChatSession,
  normalizeChatMode
} from '../pages/chat/ChatSessionTypes';

const CHAT_SESSION_DIR: string = 'chat-sessions';
const CHAT_SESSION_RECORD_DIR: string = 'sessions';
const CHAT_SESSION_INDEX_FILE: string = 'session-index.json';

export class ChatSessionStorage {
  static rootDir(filesDir: string): string {
    return filesDir + '/' + CHAT_SESSION_DIR;
  }

  static sessionsDir(filesDir: string): string {
    return ChatSessionStorage.rootDir(filesDir) + '/' + CHAT_SESSION_RECORD_DIR;
  }

  static indexPath(filesDir: string): string {
    return ChatSessionStorage.rootDir(filesDir) + '/' + CHAT_SESSION_INDEX_FILE;
  }

  static sessionFileName(sessionId: string): string {
    return sessionId + '.json';
  }

  static sessionPath(filesDir: string, sessionId: string): string {
    return ChatSessionStorage.sessionsDir(filesDir) + '/' + ChatSessionStorage.sessionFileName(sessionId);
  }

  static pathExists(path: string): boolean {
    try {
      return fs.accessSync(path);
    } catch (e) {
      return false;
    }
  }

  static ensureDirectory(path: string): void {
    try {
      if (!ChatSessionStorage.pathExists(path)) {
        fs.mkdirSync(path);
      }
    } catch (e) {
      try {
        fs.mkdirSync(path);
      } catch (err) {
      }
    }
  }

  static ensureWorkspace(filesDir: string): void {
    ChatSessionStorage.ensureDirectory(ChatSessionStorage.rootDir(filesDir));
    ChatSessionStorage.ensureDirectory(ChatSessionStorage.sessionsDir(filesDir));
  }

  static readText(path: string): string {
    let file = fs.openSync(path, fs.OpenMode.READ_ONLY);
    try {
      let stat = fs.statSync(path);
      let buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      return decodeUtf8Compat(new Uint8Array(buf));
    } finally {
      fs.closeSync(file);
    }
  }

  static writeText(path: string, content: string): void {
    let encoded = encodeUtf8Compat(content);
    let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, encoded.buffer);
    } finally {
      fs.closeSync(file);
    }
  }

  static createSessionId(now: number): string {
    return 'chat-' + String(now);
  }

  static createUniqueSessionId(filesDir: string, now: number): string {
    let baseId = ChatSessionStorage.createSessionId(now);
    let sessionId = baseId;
    let suffix = 1;
    while (ChatSessionStorage.pathExists(ChatSessionStorage.sessionPath(filesDir, sessionId))) {
      sessionId = baseId + '-' + String(suffix);
      suffix += 1;
    }
    return sessionId;
  }

  static loadIndex(filesDir: string): ChatSessionSummary[] {
    ChatSessionStorage.ensureWorkspace(filesDir);
    try {
      if (!ChatSessionStorage.pathExists(ChatSessionStorage.indexPath(filesDir))) {
        return [];
      }
      let parsed = parseJsonCompat<ChatSessionIndex>(ChatSessionStorage.readText(ChatSessionStorage.indexPath(filesDir)));
      return ChatSessionStorage.sortSessions(parsed.sessions === undefined ? [] : parsed.sessions);
    } catch (e) {
      try {
        let brokenPath = ChatSessionStorage.indexPath(filesDir) + '.broken.' + String(new Date().getTime());
        ChatSessionStorage.writeText(brokenPath, ChatSessionStorage.readText(ChatSessionStorage.indexPath(filesDir)));
      } catch (err) {
      }
      return [];
    }
  }

  static saveIndex(filesDir: string, sessions: ChatSessionSummary[]): void {
    ChatSessionStorage.ensureWorkspace(filesDir);
    let index: ChatSessionIndex = { sessions: ChatSessionStorage.sortSessions(sessions) };
    ChatSessionStorage.writeText(ChatSessionStorage.indexPath(filesDir), stringifyJsonCompat(index as Object, 2));
  }

  static sortSessions(sessions: ChatSessionSummary[]): ChatSessionSummary[] {
    let sorted = sessions.slice();
    sorted.sort((left: ChatSessionSummary, right: ChatSessionSummary) => {
      if (left.updatedAt !== right.updatedAt) {
        return right.updatedAt - left.updatedAt;
      }
      if (left.title === right.title) {
        return 0;
      }
      return left.title > right.title ? 1 : -1;
    });
    return sorted;
  }

  static createSession(filesDir: string, mode: string, now: number = new Date().getTime()): ChatSessionRecord {
    ChatSessionStorage.ensureWorkspace(filesDir);
    let session = createEmptyChatSession(ChatSessionStorage.createUniqueSessionId(filesDir, now), normalizeChatMode(mode), now);
    ChatSessionStorage.saveSession(filesDir, session);
    return session;
  }

  static loadSession(filesDir: string, sessionId: string): ChatSessionRecord | null {
    ChatSessionStorage.ensureWorkspace(filesDir);
    try {
      let session = parseJsonCompat<ChatSessionRecord>(ChatSessionStorage.readText(ChatSessionStorage.sessionPath(filesDir, sessionId)));
      session.mode = normalizeChatMode(session.mode);
      session.messages = session.messages === undefined ? [] : session.messages;
      return session;
    } catch (e) {
      ChatSessionStorage.removeFromIndex(filesDir, sessionId);
      return null;
    }
  }

  static saveSession(filesDir: string, session: ChatSessionRecord): void {
    ChatSessionStorage.ensureWorkspace(filesDir);
    let normalized: ChatSessionRecord = {
      id: session.id,
      title: session.title,
      mode: normalizeChatMode(session.mode),
      createdAt: session.createdAt,
      updatedAt: session.updatedAt,
      messages: session.messages.slice()
    };
    ChatSessionStorage.writeText(ChatSessionStorage.sessionPath(filesDir, normalized.id),
      stringifyJsonCompat(normalized as Object, 2));
    ChatSessionStorage.upsertSummary(filesDir,
      buildChatSessionSummary(normalized, ChatSessionStorage.sessionFileName(normalized.id)));
  }

  static appendMessage(filesDir: string, sessionId: string, message: ChatMessage): ChatSessionRecord | null {
    let session = ChatSessionStorage.loadSession(filesDir, sessionId);
    if (session === null) {
      return null;
    }
    session.messages = session.messages.concat([message]);
    session.updatedAt = message.createdAt;
    ChatSessionStorage.saveSession(filesDir, session);
    return session;
  }

  static upsertSummary(filesDir: string, summary: ChatSessionSummary): void {
    let sessions = ChatSessionStorage.loadIndex(filesDir).filter((item: ChatSessionSummary) => item.id !== summary.id);
    sessions.push(summary);
    ChatSessionStorage.saveIndex(filesDir, sessions);
  }

  static removeFromIndex(filesDir: string, sessionId: string): void {
    let sessions = ChatSessionStorage.loadIndex(filesDir).filter((item: ChatSessionSummary) => item.id !== sessionId);
    ChatSessionStorage.saveIndex(filesDir, sessions);
  }

  static deleteSession(filesDir: string, sessionId: string): boolean {
    ChatSessionStorage.ensureWorkspace(filesDir);
    let path = ChatSessionStorage.sessionPath(filesDir, sessionId);
    if (ChatSessionStorage.pathExists(path)) {
      try {
        fs.unlinkSync(path);
      } catch (e) {
        return false;
      }
    }
    ChatSessionStorage.removeFromIndex(filesDir, sessionId);
    return true;
  }

  static nextSessionAfterDelete(filesDir: string, deletedId: string): ChatSessionSummary | null {
    let sessions = ChatSessionStorage.loadIndex(filesDir).filter((item: ChatSessionSummary) => item.id !== deletedId);
    return sessions.length > 0 ? sessions[0] : null;
  }
}
