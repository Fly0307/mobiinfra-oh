import { describe, it, expect } from '@ohos/hypium';
import {
  buildMobileGuiWorkflowTask,
  buildMobileGuiWorkflowTaskDescription,
  classifyMobileGuiWorkflowFailure,
  mobileGuiTaskRunResultFromFailure,
  mobileGuiTaskRunResultFromWorkflowResult
} from '../main/ets/utils/MobileGuiTaskWorkflowAdapter';
import { MobileGuiTaskRequest } from '../main/ets/utils/MobileGuiTaskTypes';
import { parseJsonCompat } from '../main/ets/utils/JsonCompat';
import { resolveWorkflowJsonForRun } from '../main/ets/utils/WorkflowRunner';
import { WorkflowRunResult, WorkflowTask } from '../main/ets/utils/WorkflowTypes';

interface WorkflowJsonObject {
  steps?: WorkflowJsonStep[];
}

interface WorkflowJsonStep {
  type?: string;
  task_description?: string;
  package_name?: string;
}

function mobileGuiRequest(): MobileGuiTaskRequest {
  return {
    task: '打开微信查看今天的消息',
    appName: '微信',
    packageName: 'com.tencent.mm',
    maxSteps: 18
  };
}

export default function mobileGuiTaskWorkflowAdapterUnitTest() {
  describe('mobileGuiTaskWorkflowAdapterUnitTest', () => {
    it('buildsTaskDescriptionWithAppHints', 0, () => {
      let description = buildMobileGuiWorkflowTaskDescription(mobileGuiRequest());

      expect(description.indexOf('打开微信查看今天的消息') >= 0).assertTrue();
      expect(description.indexOf('目标应用名称提示：微信') >= 0).assertTrue();
      expect(description.indexOf('目标应用包名提示：com.tencent.mm') >= 0).assertTrue();
      expect(description.indexOf('最大步骤建议：18') >= 0).assertTrue();
    });

    it('buildsTemporaryWorkflowTaskWithoutPersistingIndex', 0, () => {
      let task: WorkflowTask = buildMobileGuiWorkflowTask(mobileGuiRequest());
      let workflow = parseJsonCompat<WorkflowJsonObject>(task.workflowJson);

      expect(task.id).assertEqual('chat-mobile-gui-task');
      expect(task.configFileName).assertEqual('__chat_mobile_gui_task.json');
      expect(task.useEmbeddedWorkflowJson).assertTrue();
      expect(workflow.steps !== undefined).assertTrue();
      expect((workflow.steps as WorkflowJsonStep[]).length).assertEqual(2);
      expect((workflow.steps as WorkflowJsonStep[])[0].type).assertEqual('gui_task');
      expect((workflow.steps as WorkflowJsonStep[])[1].type).assertEqual('gui_task');
      expect(((workflow.steps as WorkflowJsonStep[])[0].task_description || '').indexOf('com.tencent.mm') >= 0).assertTrue();
      expect((workflow.steps as WorkflowJsonStep[])[0].package_name).assertEqual('com.tencent.mm');
    });

    it('classifiesWorkflowFailureMessages', 0, () => {
      expect(classifyMobileGuiWorkflowFailure('Planner JSON 解析失败，终止执行，不再进入 Decider')).assertEqual(
        'planner_unavailable');
      expect(classifyMobileGuiWorkflowFailure('Decider request timeout after 60000ms')).assertEqual('timeout');
      expect(classifyMobileGuiWorkflowFailure('HDC bridge 返回失败：app_start failed')).assertEqual('app_start_failed');
      expect(classifyMobileGuiWorkflowFailure('current app identity mismatch: expected com.tencent.mm')).assertEqual(
        'app_identity_mismatch');
      expect(classifyMobileGuiWorkflowFailure('Planner request failed: Cloud HTTP 503 service unavailable')).assertEqual(
        'planner_unavailable');
      expect(classifyMobileGuiWorkflowFailure('Decider request failed: Cloud HTTP 502 bad gateway')).assertEqual(
        'decider_unavailable');
      expect(classifyMobileGuiWorkflowFailure('Planner request failed: connect ECONNREFUSED 127.0.0.1:8000')).assertEqual(
        'planner_unavailable');
      expect(classifyMobileGuiWorkflowFailure('Decider request failed: socket hang up')).assertEqual(
        'decider_unavailable');
      expect(classifyMobileGuiWorkflowFailure('unknown failure')).assertEqual('workflow_failed');
    });

    it('prefersEmbeddedWorkflowJsonOverDiskConfigForChatTask', 0, () => {
      let task: WorkflowTask = buildMobileGuiWorkflowTask(mobileGuiRequest());
      let selected = resolveWorkflowJsonForRun('/tmp/files', task, (_filesDir: string, _task: WorkflowTask): string => {
        return '{"steps":[{"id":"1","type":"gui_action","action":"tap"}]}';
      });

      expect(selected).assertEqual(task.workflowJson);
      expect(selected.indexOf('"gui_task"') >= 0).assertTrue();
      expect(selected.indexOf('"gui_action"') >= 0).assertFalse();
    });

    it('readsLatestDiskWorkflowForNormalTask', 0, () => {
      let task: WorkflowTask = {
        id: 'normal-task',
        sceneId: 0,
        icon: 'List',
        iconColor: '#000000',
        title: '普通任务',
        source: 'normal',
        enabled: true,
        configFileName: 'normal.json',
        workflowJson: '{"steps":[{"id":"1","type":"gui_task","task_description":"embedded"}]}',
        lastStatus: '',
        lastRun: '',
        lastMessage: ''
      };
      let selected = resolveWorkflowJsonForRun('/tmp/files', task, (_filesDir: string, _task: WorkflowTask): string => {
        return '{"steps":[{"id":"1","type":"gui_task","task_description":"latest"}]}';
      });

      expect(selected.indexOf('"latest"') >= 0).assertTrue();
      expect(selected.indexOf('"embedded"') >= 0).assertFalse();
    });

    it('mapsWorkflowRunResultToMobileGuiRunResult', 0, () => {
      let result: WorkflowRunResult = {
        status: 'failed',
        message: 'Decider service timeout',
        runDir: '/tmp/files/chat-sessions/tool-runs/session-1/mobile-gui/run-1',
        dailyLogPath: '',
        returnedToApp: false
      };
      let mapped = mobileGuiTaskRunResultFromWorkflowResult('/tmp/files', result);

      expect(mapped.ok).assertFalse();
      expect(mapped.status).assertEqual('failed');
      expect(mapped.errorCode).assertEqual('timeout');
      expect(mapped.runDir).assertEqual('chat-sessions/tool-runs/session-1/mobile-gui/run-1');
    });

    it('mapsCancelledWorkflowResultToUserCancelled', 0, () => {
      let result: WorkflowRunResult = {
        status: 'cancelled',
        message: '用户取消 workflow',
        runDir: '/tmp/files/chat-sessions/tool-runs/session-1/mobile-gui/run-2',
        dailyLogPath: '',
        returnedToApp: true
      };
      let mapped = mobileGuiTaskRunResultFromWorkflowResult('/tmp/files', result);

      expect(mapped.ok).assertFalse();
      expect(mapped.status).assertEqual('cancelled');
      expect(mapped.errorCode).assertEqual('user_cancelled');
      expect(mapped.returnedToApp).assertTrue();
    });

    it('createsDirectFailureResultForPreflightChecks', 0, () => {
      let result = mobileGuiTaskRunResultFromFailure('hdc_unavailable', 'HDC Server 未连接', true);

      expect(result.ok).assertFalse();
      expect(result.status).assertEqual('failed');
      expect(result.errorCode).assertEqual('hdc_unavailable');
      expect(result.error).assertEqual('HDC Server 未连接');
    });
  });
}
