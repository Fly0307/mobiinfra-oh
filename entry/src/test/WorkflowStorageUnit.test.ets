import { describe, it, expect } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import { RawWorkflowResourceReader, WorkflowStorage } from '../main/ets/utils/WorkflowStorage';
import { CloudModelClient, CloudModelConfig } from '../main/ets/utils/CloudModelClient';
import { WorkflowRunner } from '../main/ets/utils/WorkflowRunner';
import { WorkflowDefinition, WorkflowManagedFile, WorkflowStep, WorkflowTask } from '../main/ets/utils/WorkflowTypes';
import { parseJsonCompat } from '../main/ets/utils/JsonCompat';

function findWeixinChatSummaryQuestion(steps: WorkflowStep[]): string {
  for (let i = 0; i < steps.length; i++) {
    let step = steps[i];
    if (step.type === 'tool' && step.tool_name === 'vlm_qa' && step.inputs && step.inputs.mode === 'summary' &&
      step.inputs.question && step.inputs.question.indexOf('聊天') >= 0) {
      return step.inputs.question;
    }
    if (step.steps) {
      let nestedQuestion = findWeixinChatSummaryQuestion(step.steps);
      if (nestedQuestion.length > 0) {
        return nestedQuestion;
      }
    }
    if (step.then_steps) {
      let thenQuestion = findWeixinChatSummaryQuestion(step.then_steps);
      if (thenQuestion.length > 0) {
        return thenQuestion;
      }
    }
    if (step.else_steps) {
      let elseQuestion = findWeixinChatSummaryQuestion(step.else_steps);
      if (elseQuestion.length > 0) {
        return elseQuestion;
      }
    }
  }
  return '';
}

class FailingRawWorkflowResourceReader implements RawWorkflowResourceReader {
  private requestedPaths: string[];

  constructor(requestedPaths: string[]) {
    this.requestedPaths = requestedPaths;
  }

  getRawFileContentSync(path: string): Uint8Array {
    this.requestedPaths.push(path);
    throw new Error('missing raw workflow resource: ' + path);
  }
}

class NoopCloudModelClient extends CloudModelClient {
  async chatPlanner(_prompt: string, _config: CloudModelConfig): Promise<string> {
    throw new Error('chatPlanner should not be called in this test');
  }

  async chatQwenDecider(_task: string, _historyItems: string[], _imageBase64: string,
    _config: CloudModelConfig): Promise<string> {
    throw new Error('chatQwenDecider should not be called in this test');
  }
}

let testRootCounter: number = 0;

function nextTestRoot(name: string): string {
  testRootCounter += 1;
  return '/tmp/workflow-storage-unit-' + name + '-' + String(new Date().getTime()) + '-' + String(testRootCounter);
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
  try {
    fs.mkdirSync(path);
  } catch (e) {
  }
}

export default function workflowStorageUnitTest() {
  describe('workflowStorageUnitTest', () => {
    it('sortManagedFilesForDisplayUsesLatestFilesFirst', 0, () => {
      let files: WorkflowManagedFile[] = [
        { name: 'b.md', path: '/tmp/b.md', size: 20, modifiedTime: 200 },
        { name: 'a.md', path: '/tmp/a.md', size: 10, modifiedTime: 200 },
        { name: 'c.md', path: '/tmp/c.md', size: 30, modifiedTime: 100 }
      ];

      let sorted = WorkflowStorage.sortManagedFilesForDisplay(files);

      expect(sorted[0].name).assertEqual('a.md');
      expect(sorted[1].name).assertEqual('b.md');
      expect(sorted[2].name).assertEqual('c.md');
    });

    it('workflowImageInputRecognizesBase64AndPath', 0, () => {
      let base64 = '/9j/4AAQSkZJRgABAQAAAQABAAD';
      expect(WorkflowStorage.workflowImageInputKind(base64)).assertEqual('base64');
      expect(WorkflowStorage.workflowImageInputKind('data:image/jpeg;base64,' + base64)).assertEqual('data_uri');
      expect(WorkflowStorage.workflowImageInputKind('/data/storage/el2/base/files/workflows/runs/demo/steps/1/screenshot.jpg'))
        .assertEqual('path');
      expect(WorkflowStorage.workflowImageInputKind('workflows/runs/demo/steps/1/screenshot.jpg')).assertEqual('path');
    });

    it('workflowScreenshotRelativePathUsesConcreteImageFile', 0, () => {
      let relative = WorkflowStorage.workflowRunRelativePath(
        '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files',
        '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files/workflows/runs/20260608-103333-basic-gui-task/steps/3/screenshot.jpg'
      );
      expect(relative).assertEqual('workflows/runs/20260608-103333-basic-gui-task/steps/3/screenshot.jpg');
      expect(relative.endsWith('/steps/3')).assertFalse();
    });

    it('chatSessionMobileGuiToolRunRootSanitizesSessionId', 0, () => {
      expect(WorkflowStorage.chatSessionMobileGuiToolRunRoot('/tmp/files', 'session-abc'))
        .assertEqual('/tmp/files/chat-sessions/tool-runs/session-abc/mobile-gui');
      expect(WorkflowStorage.chatSessionMobileGuiToolRunRoot('/tmp/files', 'sess/ion id'))
        .assertEqual('/tmp/files/chat-sessions/tool-runs/sess_ion_id/mobile-gui');
      expect(WorkflowStorage.chatSessionMobileGuiToolRunRoot('/tmp/files', ''))
        .assertEqual('/tmp/files/chat-sessions/tool-runs/unknown/mobile-gui');
    });

    it('ensureChatSessionMobileGuiToolRunRootCreatesAndReturnsRoot', 0, () => {
      let filesDir = nextTestRoot('ensure-chat-session-root');
      prepareTestRoot(filesDir);

      let root = WorkflowStorage.ensureChatSessionMobileGuiToolRunRoot(filesDir, 'session/abc');

      expect(root).assertEqual(filesDir + '/chat-sessions/tool-runs/session_abc/mobile-gui');
      expect(fs.accessSync(root)).assertTrue();
      expect(fs.accessSync(filesDir + '/chat-sessions/tool-runs/session_abc')).assertTrue();

      cleanupPath(filesDir);
    });

    it('workflowRunRelativePathPreservesChatSessionRelativePaths', 0, () => {
      let filesDir = '/tmp/files';
      let absolutePath = '/tmp/files/chat-sessions/tool-runs/session-abc/mobile-gui/run-1/run_summary.json';
      expect(WorkflowStorage.workflowRunRelativePath(filesDir, absolutePath))
        .assertEqual('chat-sessions/tool-runs/session-abc/mobile-gui/run-1/run_summary.json');
      expect(WorkflowStorage.workflowRunRelativePath(filesDir,
        'chat-sessions/tool-runs/session-abc/mobile-gui/run-1/run_summary.json'))
        .assertEqual('chat-sessions/tool-runs/session-abc/mobile-gui/run-1/run_summary.json');
    });

    it('workflowRunnerUsesRunRootOverrideForRunDir', 0, async () => {
      let filesDir = nextTestRoot('runner-override');
      prepareTestRoot(filesDir);
      let overrideRoot = WorkflowStorage.ensureChatSessionMobileGuiToolRunRoot(filesDir, 'session-abc');
      let client = new NoopCloudModelClient();
      let runner = new WorkflowRunner(filesDir, client, (): CloudModelConfig => {
        return {
          plannerBaseUrl: 'http://127.0.0.1:1',
          deciderBaseUrl: 'http://127.0.0.1:1',
          apiKey: 'test-key',
          deciderModel: 'test-model'
        };
      }, 'http://127.0.0.1:1', (): void => {
      }, overrideRoot);
      let task: WorkflowTask = {
        id: 'runner_override_task',
        sceneId: 0,
        icon: 'Tool',
        iconColor: '#000000',
        title: 'runner override test',
        source: 'chat-session',
        enabled: true,
        configFileName: 'runner_override_task.json',
        workflowJson: '{"steps":[{"id":"1","type":"if","condition":false,"then_steps":[],"else_steps":[]}]}',
        lastStatus: '未运行',
        lastRun: '尚未执行',
        lastMessage: 'test'
      };

      let result = await runner.runTask(task);

      expect(result.runDir.indexOf(overrideRoot)).assertEqual(0);
      expect(fs.accessSync(result.runDir)).assertTrue();

      cleanupPath(filesDir);
    });

    it('runSummaryDeleteTargetUsesWholeRunDirectory', 0, () => {
      let filesDir = '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files';
      let file: WorkflowManagedFile = {
        name: '20260609-104256-basic-gui-task/run_summary.json',
        path: filesDir + '/workflows/runs/20260609-104256-basic-gui-task/run_summary.json',
        size: 128,
        modifiedTime: 0
      };

      expect(WorkflowStorage.managedFileDeleteTarget(filesDir, 'run', file))
        .assertEqual(filesDir + '/workflows/runs/20260609-104256-basic-gui-task');
    });

    it('rootConfigDeleteTargetKeepsSingleConfigFile', 0, () => {
      let filesDir = '/data/app/el2/100/base/com.example.mnnllmchat/haps/entry/files';
      let file: WorkflowManagedFile = {
        name: 'default_ele_order.json',
        path: filesDir + '/workflows/configs/default_ele_order.json',
        size: 128,
        modifiedTime: 0
      };

      expect(WorkflowStorage.managedFileDeleteTarget(filesDir, 'config', file)).assertEqual(file.path);
    });

    it('defaultWeixinSummaryPromptRequiresChatTimeAnchors', 0, () => {
      let workflow = parseJsonCompat<WorkflowDefinition>(WorkflowStorage.defaultWeixinWorkflow());
      let question = findWeixinChatSummaryQuestion(workflow.steps);

      expect(question.length > 0).assertTrue();
      expect(question.indexOf('聊天对象') >= 0).assertTrue();
      expect(question.indexOf('当前聊天对象') >= 0).assertTrue();
      expect(question.indexOf('消息发送绝对时间') >= 0).assertTrue();
      expect(question.indexOf('聊天日期分隔符') >= 0).assertTrue();
      expect(question.indexOf('同一时间锚点') >= 0).assertTrue();
      expect(question.indexOf('只有截图中完全没有聊天时间锚点时') >= 0).assertTrue();
      expect(question.indexOf('任务执行时间') >= 0).assertTrue();
      expect(question.indexOf('事件相对时间') >= 0).assertTrue();
      expect(question.indexOf('事件绝对时间') >= 0).assertTrue();
      let forbiddenTimeEventsKey = 'time' + '_events';
      expect(question.indexOf(forbiddenTimeEventsKey)).assertEqual(-1);
    });

    it('codeDefinedDefaultTaskUsesLatestWorkflowUnlessUserModified', 0, () => {
      let defaultTask: WorkflowTask = {
        id: 'default_weixin_chat',
        sceneId: 3,
        icon: 'Chat',
        iconColor: '#FF9347',
        title: '收集指定微信用户近3页的聊天记录',
        source: 'basic-gui-task',
        enabled: true,
        configFileName: 'default_weixin_chat.json',
        workflowJson: '{"version":"new-code-default"}',
        lastStatus: '未运行',
        lastRun: '尚未执行',
        lastMessage: '点击运行后开始执行 workflow'
      };
      let storedTask: WorkflowTask = {
        id: 'default_weixin_chat',
        sceneId: 3,
        icon: 'Chat',
        iconColor: '#FF9347',
        title: '收集指定微信用户近3页的聊天记录',
        source: 'basic-gui-task',
        enabled: false,
        configFileName: 'default_weixin_chat.json',
        workflowJson: '{"version":"old-stored-default"}',
        lastStatus: '已完成',
        lastRun: '2026/6/9 04:42:00',
        lastMessage: '最近运行完成'
      };

      let synced = WorkflowStorage.mergeCodeDefinedDefaultTaskForTest(defaultTask, storedTask);
      expect(synced.workflowJson).assertEqual(defaultTask.workflowJson);
      expect(synced.enabled).assertFalse();
      expect(synced.lastStatus).assertEqual('已完成');
      expect(synced.lastRun).assertEqual('2026/6/9 04:42:00');

      let modifiedTask: WorkflowTask = {
        id: storedTask.id,
        sceneId: storedTask.sceneId,
        icon: storedTask.icon,
        iconColor: storedTask.iconColor,
        title: storedTask.title,
        source: storedTask.source,
        enabled: storedTask.enabled,
        configFileName: storedTask.configFileName,
        workflowJson: storedTask.workflowJson,
        lastStatus: storedTask.lastStatus,
        lastRun: storedTask.lastRun,
        lastMessage: storedTask.lastMessage,
        isUserModified: true
      };
      let preserved = WorkflowStorage.mergeCodeDefinedDefaultTaskForTest(defaultTask, modifiedTask);
      expect(preserved.workflowJson).assertEqual(storedTask.workflowJson);
      expect(preserved.isUserModified).assertTrue();
    });

    it('defaultWorkflowResourceInstallReportsRawFileFailures', 0, () => {
      let requestedPaths: string[] = [];
      let failurePaths: string[] = [];
      let failureMessages: string[] = [];
      let reader: RawWorkflowResourceReader = new FailingRawWorkflowResourceReader(requestedPaths);

      let failureCount = WorkflowStorage.installDefaultWorkflowResourcesForTest('/tmp/workflow-raw-install-failure',
        reader, (rawFilePath: string, cause: Error) => {
          failurePaths.push(rawFilePath);
          failureMessages.push(cause.message);
        });

      expect(failureCount > 0).assertTrue();
      expect(failurePaths.length).assertEqual(failureCount);
      expect(failurePaths[0].startsWith('workflows/configs/')).assertTrue();
      expect(failureMessages[0].indexOf(failurePaths[0]) >= 0).assertTrue();
      expect(requestedPaths[0]).assertEqual(failurePaths[0]);
    });
  });
}
