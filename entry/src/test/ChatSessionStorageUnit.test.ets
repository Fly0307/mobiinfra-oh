import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import {
  CHAT_MESSAGE_KIND_TASK_RESULT,
  CHAT_MESSAGE_KIND_TASK_TRACE,
  CHAT_MODE_CLOUD_AGENT,
  ChatMessage,
  buildCloudContextMessages,
  chatMessageRenderKey,
  chatSessionPreview,
  createChatMessage,
  createEmptyChatSession,
  defaultChatSessionTitle,
  toggleChatMessageCollapsed
} from '../main/ets/pages/chat/ChatSessionTypes';
import { ChatSessionController, ChatSessionViewState } from '../main/ets/pages/chat/ChatSessionController';
import { ChatSessionStorage } from '../main/ets/utils/ChatSessionStorage';

let testRootCounter: number = 0;

function nextTestRoot(name: string): string {
  testRootCounter += 1;
  return '/tmp/chat-session-storage-unit-' + name + '-' + String(new Date().getTime()) + '-' +
    String(testRootCounter);
}

function cleanupPath(path: string): void {
  try {
    let children = fs.listFileSync(path);
    for (let i = 0; i < children.length; i++) {
      cleanupPath(path + '/' + children[i]);
    }
    fs.rmdirSync(path);
  } catch (e) {
    try {
      fs.unlinkSync(path);
    } catch (err) {
    }
  }
}

function prepareTestRoot(path: string): void {
  cleanupPath(path);
  if (!ChatSessionStorage.pathExists(path)) {
    fs.mkdirSync(path);
  }
}

export default function chatSessionStorageUnitTest() {
  describe('chatSessionStorageUnitTest', () => {
    it('createsDefaultSessionWithModeAndTitle', 0, () => {
      let session = createEmptyChatSession('session-1', CHAT_MODE_CLOUD_AGENT, 1000);

      expect(session.id).assertEqual('session-1');
      expect(session.mode).assertEqual(CHAT_MODE_CLOUD_AGENT);
      expect(session.title).assertEqual(defaultChatSessionTitle(CHAT_MODE_CLOUD_AGENT));
      expect(session.messages.length).assertEqual(0);
    });

    it('buildsPreviewFromLatestUsefulMessage', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('m1', 'user', 'chat', '请整理今天截图里的关键信息', 1000),
        createChatMessage('m2', 'assistant', 'chat', '我会先读取最近截图并按主题归纳。', 1001)
      ];

      expect(chatSessionPreview(messages)).assertEqual('我会先读取最近截图并按主题归纳。');
    });

    it('keepsTaskTraceCollapsedByDefaultAndTogglesIt', 0, () => {
      let message = createChatMessage('trace-1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '执行过程', 1000,
        ['Planner started', 'Decider selected click']);

      expect(message.collapsed).assertTrue();

      let toggled = toggleChatMessageCollapsed([message], 'trace-1');

      expect(toggled[0].collapsed).assertFalse();
      expect(chatMessageRenderKey(message) === chatMessageRenderKey(toggled[0])).assertFalse();
    });

    it('cloudContextSkipsTaskTraceMessages', 0, () => {
      let messages: ChatMessage[] = [
        createChatMessage('u1', 'user', 'chat', '你好', 1000),
        createChatMessage('t1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '执行过程', 1001, ['step 1']),
        createChatMessage('r1', 'task', CHAT_MESSAGE_KIND_TASK_RESULT, '执行完成', 1002),
        createChatMessage('a1', 'assistant', 'chat', '你好，我可以帮你。', 1003)
      ];

      let context = buildCloudContextMessages(messages);

      expect(context.length).assertEqual(3);
      expect(context[0].role).assertEqual('user');
      expect(context[1].role).assertEqual('assistant');
      let taskResultContent = context[1].content as string;
      expect(taskResultContent).assertEqual('执行完成');
      expect(context[2].role).assertEqual('assistant');
    });

    it('persistsSessionIndexAndDeletesSessionFile', 0, () => {
      let root = nextTestRoot('persist');
      prepareTestRoot(root);

      let session = ChatSessionStorage.createSession(root, CHAT_MODE_CLOUD_AGENT, 1000);
      ChatSessionStorage.appendMessage(root, session.id,
        createChatMessage('m1', 'user', 'chat', '第一条消息', 1001));

      let index = ChatSessionStorage.loadIndex(root);
      expect(index.length).assertEqual(1);
      expect(index[0].messageCount).assertEqual(1);
      expect(index[0].lastMessagePreview).assertEqual('第一条消息');

      let deleted = ChatSessionStorage.deleteSession(root, session.id);
      expect(deleted).assertTrue();
      expect(ChatSessionStorage.pathExists(ChatSessionStorage.sessionPath(root, session.id))).assertFalse();

      cleanupPath(root);
    });

    it('createsUniqueSessionIdAndCleansMissingFileIndex', 0, () => {
      let root = nextTestRoot('unique');
      prepareTestRoot(root);

      let first = ChatSessionStorage.createSession(root, CHAT_MODE_CLOUD_AGENT, 1000);
      let second = ChatSessionStorage.createSession(root, CHAT_MODE_CLOUD_AGENT, 1000);

      expect(first.id).assertEqual('chat-1000');
      expect(second.id).assertEqual('chat-1000-1');

      fs.unlinkSync(ChatSessionStorage.sessionPath(root, first.id));
      let deleted = ChatSessionStorage.deleteSession(root, first.id);
      let index = ChatSessionStorage.loadIndex(root);

      expect(deleted).assertTrue();
      expect(index.length).assertEqual(1);
      expect(index[0].id).assertEqual(second.id);

      cleanupPath(root);
    });

    it('toggleTaskTracePersistsCollapsedState', 0, () => {
      let root = nextTestRoot('toggle');
      prepareTestRoot(root);

      let session = ChatSessionStorage.createSession(root, CHAT_MODE_CLOUD_AGENT, 1000);
      let trace = createChatMessage('trace-1', 'task', CHAT_MESSAGE_KIND_TASK_TRACE, '云端任务执行过程', 1001,
        ['动作：click']);
      let saved = ChatSessionStorage.appendMessage(root, session.id, trace);
      expect(saved !== null).assertTrue();

      let state: ChatSessionViewState = {
        sessions: ChatSessionStorage.loadIndex(root),
        activeSessionId: session.id,
        activeMessages: [trace],
        mode: CHAT_MODE_CLOUD_AGENT,
        activeSession: saved
      };
      let next = ChatSessionController.toggleTaskTrace(root, state, 'trace-1');
      let reloaded = ChatSessionStorage.loadSession(root, session.id);

      expect(next.activeMessages[0].collapsed).assertFalse();
      expect(reloaded !== null).assertTrue();
      if (reloaded !== null) {
        expect(reloaded.messages[0].collapsed).assertFalse();
      }

      cleanupPath(root);
    });
  });
}
