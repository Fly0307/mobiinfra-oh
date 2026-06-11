import {
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  CHAT_MODE_CLOUD_AGENT,
  ChatMessage,
  ChatSessionRecord,
  ChatSessionSummary,
  chatMessageImagePath,
  normalizeChatMode,
  toggleChatMessageCollapsed
} from './ChatSessionTypes';
import { ChatSessionStorage } from '../../utils/ChatSessionStorage';

export interface ChatSessionViewState {
  sessions: ChatSessionSummary[];
  activeSessionId: string;
  activeMessages: ChatMessage[];
  mode: string;
  activeSession: ChatSessionRecord | null;
}

export class ChatSessionController {
  static emptyState(mode: string = CHAT_MODE_CLOUD_AGENT): ChatSessionViewState {
    return {
      sessions: [],
      activeSessionId: '',
      activeMessages: [],
      mode: normalizeChatMode(mode),
      activeSession: null
    };
  }

  static init(filesDir: string, mode: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return ChatSessionController.emptyState(mode);
    }
    ChatSessionStorage.ensureWorkspace(filesDir);
    let sessions = ChatSessionStorage.loadIndex(filesDir);
    if (sessions.length === 0) {
      let session = ChatSessionStorage.createSession(filesDir, mode);
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    let firstSession = ChatSessionStorage.loadSession(filesDir, sessions[0].id);
    if (firstSession === null) {
      let session = ChatSessionStorage.createSession(filesDir, mode);
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    return ChatSessionController.stateFromSession(filesDir, firstSession);
  }

  static ensureActive(filesDir: string, state: ChatSessionViewState, mode: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return ChatSessionController.emptyState(mode);
    }
    if (state.activeSessionId.length > 0) {
      let session = ChatSessionStorage.loadSession(filesDir, state.activeSessionId);
      if (session !== null) {
        return ChatSessionController.stateFromSession(filesDir, session);
      }
    }
    let created = ChatSessionStorage.createSession(filesDir, mode);
    return ChatSessionController.stateFromSession(filesDir, created);
  }

  static appendMessage(filesDir: string, state: ChatSessionViewState, mode: string,
    message: ChatMessage): ChatSessionViewState {
    let active = ChatSessionController.ensureActive(filesDir, state, mode);
    if (active.activeSession === null) {
      return active;
    }
    let session = ChatSessionStorage.appendMessage(filesDir, active.activeSession.id, message);
    if (session === null) {
      return active;
    }
    return ChatSessionController.stateFromSession(filesDir, session);
  }

  static appendTaskTraceLine(filesDir: string, state: ChatSessionViewState, mode: string, line: string,
    messageId: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return state;
    }
    if (state.activeSessionId.length === 0) {
      return state;
    }
    let session = ChatSessionStorage.loadSession(filesDir, state.activeSessionId);
    if (session === null || session.messages.length === 0) {
      return ChatSessionController.refreshCurrent(filesDir, state);
    }
    let messages = session.messages.slice();
    let traceIndex = ChatSessionController.findTaskTraceIndex(messages, messageId);
    if (traceIndex < 0) {
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    let lastMessage = messages[traceIndex];
    let trace = lastMessage.trace.slice();
    trace.push(line);
    messages[traceIndex] = {
      id: lastMessage.id,
      role: lastMessage.role,
      kind: lastMessage.kind,
      content: lastMessage.content,
      trace: trace,
      collapsed: lastMessage.collapsed,
      createdAt: lastMessage.createdAt,
      imagePath: chatMessageImagePath(lastMessage)
    };
    session.messages = messages;
    session.updatedAt = new Date().getTime();
    ChatSessionStorage.saveSession(filesDir, session);
    return ChatSessionController.stateFromSession(filesDir, session);
  }

  static attachTaskResultImage(filesDir: string, state: ChatSessionViewState, sessionId: string,
    imagePath: string): ChatSessionViewState {
    if (filesDir.length === 0 || sessionId.length === 0 || imagePath.length === 0) {
      return state;
    }
    let session = ChatSessionStorage.loadSession(filesDir, sessionId);
    if (session === null) {
      return ChatSessionController.refreshCurrent(filesDir, state);
    }
    let messages = session.messages.slice();
    let resultIndex = ChatSessionController.findLatestTaskResultIndex(messages);
    if (resultIndex < 0) {
      return ChatSessionController.stateAfterBackgroundSessionUpdate(filesDir, state);
    }
    let sessionImagePath = ChatSessionStorage.adoptImageForSession(filesDir, sessionId, imagePath);
    let resultMessage = messages[resultIndex];
    messages[resultIndex] = {
      id: resultMessage.id,
      role: resultMessage.role,
      kind: resultMessage.kind,
      content: resultMessage.content,
      trace: resultMessage.trace.slice(),
      collapsed: resultMessage.collapsed,
      createdAt: resultMessage.createdAt,
      imagePath: sessionImagePath
    };
    session.messages = messages;
    session.updatedAt = new Date().getTime();
    ChatSessionStorage.saveSession(filesDir, session);
    if (state.activeSessionId === sessionId) {
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    return ChatSessionController.stateAfterBackgroundSessionUpdate(filesDir, state);
  }

  static createSession(filesDir: string, state: ChatSessionViewState, mode: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return ChatSessionController.emptyState(mode);
    }
    let nextMode = mode.length > 0 ? mode : state.mode;
    let session = ChatSessionStorage.createSession(filesDir, nextMode);
    return ChatSessionController.stateFromSession(filesDir, session);
  }

  static selectSession(filesDir: string, state: ChatSessionViewState, id: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return state;
    }
    let session = ChatSessionStorage.loadSession(filesDir, id);
    if (session === null) {
      return {
        sessions: ChatSessionStorage.loadIndex(filesDir),
        activeSessionId: state.activeSessionId,
        activeMessages: state.activeMessages.slice(),
        mode: normalizeChatMode(state.mode),
        activeSession: null
      };
    }
    return ChatSessionController.stateFromSession(filesDir, session);
  }

  static switchMode(filesDir: string, state: ChatSessionViewState, mode: string): ChatSessionViewState {
    let normalizedMode = normalizeChatMode(mode);
    if (state.mode === normalizedMode && state.activeSessionId.length > 0) {
      return state;
    }
    if (filesDir.length === 0) {
      return ChatSessionController.emptyState(normalizedMode);
    }
    let sessions = ChatSessionStorage.loadIndex(filesDir);
    for (let i = 0; i < sessions.length; i++) {
      if (normalizeChatMode(sessions[i].mode) === normalizedMode) {
        return ChatSessionController.selectSession(filesDir, state, sessions[i].id);
      }
    }
    return ChatSessionController.createSession(filesDir, state, normalizedMode);
  }

  static deleteSession(filesDir: string, state: ChatSessionViewState, id: string,
    fallbackMode: string): ChatSessionViewState {
    if (filesDir.length === 0) {
      return state;
    }
    let deleted = ChatSessionStorage.deleteSession(filesDir, id);
    if (!deleted) {
      return ChatSessionController.refreshCurrent(filesDir, state);
    }
    let next = ChatSessionStorage.nextSessionAfterDelete(filesDir, id);
    if (next === null) {
      let session = ChatSessionStorage.createSession(filesDir, fallbackMode);
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    let nextSession = ChatSessionStorage.loadSession(filesDir, next.id);
    if (nextSession === null) {
      let session = ChatSessionStorage.createSession(filesDir, fallbackMode);
      return ChatSessionController.stateFromSession(filesDir, session);
    }
    return ChatSessionController.stateFromSession(filesDir, nextSession);
  }

  static toggleTaskTrace(filesDir: string, state: ChatSessionViewState, messageId: string): ChatSessionViewState {
    if (filesDir.length === 0 || state.activeSessionId.length === 0) {
      return state;
    }
    let session = ChatSessionStorage.loadSession(filesDir, state.activeSessionId);
    if (session === null) {
      return ChatSessionController.refreshCurrent(filesDir, state);
    }
    session.messages = toggleChatMessageCollapsed(session.messages, messageId);
    session.updatedAt = new Date().getTime();
    ChatSessionStorage.saveSession(filesDir, session);
    return ChatSessionController.stateFromSession(filesDir, session);
  }

  private static stateFromSession(filesDir: string, session: ChatSessionRecord): ChatSessionViewState {
    return {
      sessions: ChatSessionStorage.loadIndex(filesDir),
      activeSessionId: session.id,
      activeMessages: session.messages.slice(),
      mode: normalizeChatMode(session.mode),
      activeSession: session
    };
  }

  private static refreshCurrent(filesDir: string, state: ChatSessionViewState): ChatSessionViewState {
    if (state.activeSessionId.length > 0) {
      let session = ChatSessionStorage.loadSession(filesDir, state.activeSessionId);
      if (session !== null) {
        return ChatSessionController.stateFromSession(filesDir, session);
      }
    }
    return {
      sessions: ChatSessionStorage.loadIndex(filesDir),
      activeSessionId: '',
      activeMessages: [],
      mode: normalizeChatMode(state.mode),
      activeSession: null
    };
  }

  private static stateAfterBackgroundSessionUpdate(filesDir: string, state: ChatSessionViewState): ChatSessionViewState {
    return {
      sessions: ChatSessionStorage.loadIndex(filesDir),
      activeSessionId: state.activeSessionId,
      activeMessages: state.activeMessages.slice(),
      mode: normalizeChatMode(state.mode),
      activeSession: state.activeSession
    };
  }

  private static findTaskTraceIndex(messages: ChatMessage[], messageId: string): number {
    if (messageId.length > 0) {
      for (let i = 0; i < messages.length; i++) {
        if (messages[i].id === messageId && messages[i].kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
          return i;
        }
      }
      return -1;
    }
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].kind === CHAT_MESSAGE_KIND_TASK_TRACE) {
        return i;
      }
    }
    return -1;
  }

  private static findLatestTaskResultIndex(messages: ChatMessage[]): number {
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].kind === CHAT_MESSAGE_KIND_TASK_RESULT) {
        return i;
      }
    }
    return -1;
  }
}
