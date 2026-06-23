import { describe, it, expect } from '@ohos/hypium';
import {
  MOBILE_GUI_TASK_TOOL_NAME,
  createMobileGuiTaskTool,
  mobileGuiTaskToolParameters,
  MobileGuiTaskRunResult,
  MobileGuiTaskToolResponse,
  mobileGuiTaskToolResponseFromRunResult,
  normalizeMobileGuiTaskArguments,
  stringifyMobileGuiTaskToolResponse
} from '../main/ets/utils/MobileGuiTaskTool';
import { ChatToolExecutionContext } from '../main/ets/utils/ChatToolRegistry';
import { parseJsonCompat } from '../main/ets/utils/JsonCompat';

interface TestSchemaObject {
  type?: string;
  additionalProperties?: boolean;
  required?: string[];
  properties?: Record<string, Object>;
}

interface TestPayload {
  ok?: boolean;
  status?: string;
  summary?: string;
  run_dir?: string;
  returned_to_app?: boolean;
  error_code?: string;
  error?: string;
  recoverable?: boolean;
}

function testContext(): ChatToolExecutionContext {
  return {
    filesDir: '',
    sessionId: 'test-session',
    userMessage: '测试手机 GUI 工具'
  };
}

export default function mobileGuiTaskToolUnitTest() {
  describe('mobileGuiTaskToolUnitTest', () => {
    it('exposesToolNameAndStrictSchemaForTask', 0, () => {
      let tool = createMobileGuiTaskTool();
      let schema = mobileGuiTaskToolParameters() as TestSchemaObject;

      expect(tool.name).assertEqual(MOBILE_GUI_TASK_TOOL_NAME);
      expect(schema.type).assertEqual('object');
      expect(schema.additionalProperties).assertFalse();
      expect(schema.required !== undefined).assertTrue();
      expect((schema.required as string[]).indexOf('task') >= 0).assertTrue();
    });

    it('normalizesValidArgumentsWithAppHintsAndMaxSteps', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开饿了么查看订单","app_name":"饿了么",' +
        '"package_name":"me.ele","max_steps":12}');

      expect(validation.ok).assertTrue();
      expect(validation.request.task).assertEqual('打开饿了么查看订单');
      expect(validation.request.appName).assertEqual('饿了么');
      expect(validation.request.packageName).assertEqual('me.ele');
      expect(validation.request.maxSteps).assertEqual(12);
    });

    it('rejectsEmptyTaskAsInvalidArguments', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"   "}');

      expect(validation.ok).assertFalse();
      expect(validation.errorCode).assertEqual('invalid_arguments');
    });

    it('rejectsUnknownFieldsAsInvalidArguments', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开微信","foo":"bar"}');

      expect(validation.ok).assertFalse();
      expect(validation.errorCode).assertEqual('invalid_arguments');
    });

    it('fallsBackToDefaultMaxStepsForNegativeValues', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开微信","max_steps":-1}');

      expect(validation.ok).assertTrue();
      expect(validation.request.maxSteps).assertEqual(20);
    });

    it('capsMaxStepsAtFiftyForLargeValues', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开微信","max_steps":99}');

      expect(validation.ok).assertTrue();
      expect(validation.request.maxSteps).assertEqual(50);
    });

    it('mapsSuccessfulRunResultToSnakeCaseWirePayload', 0, () => {
      let result: MobileGuiTaskRunResult = {
        ok: true,
        status: 'success',
        errorCode: '',
        error: '',
        recoverable: false,
        summary: '已完成',
        runDir: '/tmp/run-1',
        returnedToApp: true
      };

      let response: MobileGuiTaskToolResponse = mobileGuiTaskToolResponseFromRunResult(result);
      let payload = parseJsonCompat<TestPayload>(stringifyMobileGuiTaskToolResponse(response));

      expect(payload.ok).assertTrue();
      expect(payload.status).assertEqual('success');
      expect(payload.summary).assertEqual('已完成');
      expect(payload.run_dir).assertEqual('/tmp/run-1');
      expect(payload.returned_to_app).assertTrue();
      expect(payload.error_code === undefined).assertTrue();
      expect(payload.error === undefined).assertTrue();
      expect(payload.recoverable === undefined).assertTrue();
    });

    it('mapsFailedRunResultToSnakeCaseWirePayload', 0, () => {
      let result: MobileGuiTaskRunResult = {
        ok: false,
        status: 'failed',
        errorCode: 'tool_failed',
        error: '执行失败',
        recoverable: true,
        summary: '',
        runDir: '/tmp/run-2',
        returnedToApp: false
      };

      let response: MobileGuiTaskToolResponse = mobileGuiTaskToolResponseFromRunResult(result);
      let payload = parseJsonCompat<TestPayload>(stringifyMobileGuiTaskToolResponse(response));

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('failed');
      expect(payload.error_code).assertEqual('tool_failed');
      expect(payload.error).assertEqual('执行失败');
      expect(payload.recoverable).assertTrue();
    });

    it('returnsUnavailablePayloadForValidExecutionWithoutCallback', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信","app_name":"微信"}', testContext());
      let payload = parseJsonCompat<TestPayload>(output);

      expect(payload.ok).assertFalse();
      expect(payload.error_code).assertEqual('unavailable');
      expect(payload.recoverable).assertTrue();
      expect(payload.status).assertEqual('unavailable');
    });
  });
}
