import { describe, it, expect } from '@ohos/hypium';
import {
  MOBILE_GUI_TASK_TOOL_NAME,
  createMobileGuiTaskConfirmationCancelledError,
  createMobileGuiTaskTool,
  isMobileGuiTaskConfirmationCancelledError,
  mobileGuiTaskToolParameters,
  MobileGuiTaskToolResponse,
  mobileGuiTaskToolResponseFromRunResult,
  normalizeMobileGuiTaskArguments,
  stringifyMobileGuiTaskToolResponse
} from '../main/ets/utils/MobileGuiTaskTool';
import { ChatToolExecutionContext } from '../main/ets/utils/ChatToolRegistry';
import {
  MobileGuiTaskBusinessResult,
  MobileGuiTaskJsonValue,
  MobileGuiTaskRequest,
  MobileGuiTaskRunResult
} from '../main/ets/utils/MobileGuiTaskTypes';
import { parseJsonCompat } from '../main/ets/utils/JsonCompat';

interface TestSchemaObject {
  type?: string;
  additionalProperties?: boolean;
  required?: string[];
}

interface MobileGuiTaskCallbackOverrides {
  confirmMobileGuiTask?: (request: MobileGuiTaskRequest) => Promise<boolean>;
  runMobileGuiTask?: (request: MobileGuiTaskRequest) => Promise<MobileGuiTaskRunResult>;
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
  result?: MobileGuiTaskBusinessResult;
}

function testContext(): ChatToolExecutionContext {
  return {
    filesDir: '',
    sessionId: 'test-session',
    userMessage: '测试手机 GUI 工具'
  };
}

function testContextWithCallbacks(overrides?: MobileGuiTaskCallbackOverrides): ChatToolExecutionContext {
  let context: ChatToolExecutionContext = testContext();
  if (overrides !== undefined && overrides.confirmMobileGuiTask !== undefined) {
    context.confirmMobileGuiTask = overrides.confirmMobileGuiTask;
  }
  if (overrides !== undefined && overrides.runMobileGuiTask !== undefined) {
    context.runMobileGuiTask = overrides.runMobileGuiTask;
  }
  return context;
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

    it('normalizesValidArgumentsWithTaskAndMaxStepsOnly', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开饿了么查看订单","max_steps":12}');

      expect(validation.ok).assertTrue();
      expect(validation.request.task).assertEqual('打开饿了么查看订单');
      expect(validation.request.maxSteps).assertEqual(12);
    });

    it('rejectsAppHintsAsInvalidArguments', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开微信","app_name":"微信",' +
        '"package_name":"com.tencent.wechat"}');

      expect(validation.ok).assertFalse();
      expect(validation.errorCode).assertEqual('invalid_arguments');
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

    it('keepsToolStatusSeparateFromBusinessOutcomeInWirePayload', 0, () => {
      let keyValues: Record<string, MobileGuiTaskJsonValue> = {};
      keyValues['order_count'] = 0;
      let items: Object[] = [];
      let businessResult: MobileGuiTaskBusinessResult = {
        outcome: 'empty',
        summary: '没有待处理订单',
        key_values: keyValues,
        items: items
      };
      let result: MobileGuiTaskRunResult = {
        ok: true,
        status: 'completed',
        errorCode: '',
        error: '',
        recoverable: false,
        summary: '没有待处理订单',
        runDir: '/tmp/run-1',
        returnedToApp: true,
        result: businessResult
      };

      let response: MobileGuiTaskToolResponse = mobileGuiTaskToolResponseFromRunResult(result);
      let payload = parseJsonCompat<TestPayload>(stringifyMobileGuiTaskToolResponse(response));

      expect(payload.ok).assertTrue();
      expect(payload.status).assertEqual('completed');
      expect(payload.result !== undefined).assertTrue();
      expect(payload.result!.outcome).assertEqual('empty');
      expect(payload.result!.summary).assertEqual('没有待处理订单');
      expect(payload.result!.key_values['order_count']).assertEqual(0);
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

    it('omitsBusinessResultFromFailedWirePayload', 0, () => {
      let keyValues: Record<string, MobileGuiTaskJsonValue> = {};
      keyValues['stale'] = true;
      let items: Object[] = [];
      let businessResult: MobileGuiTaskBusinessResult = {
        outcome: 'completed',
        summary: '陈旧业务结果',
        key_values: keyValues,
        items: items
      };
      let result: MobileGuiTaskRunResult = {
        ok: false,
        status: 'failed',
        errorCode: 'tool_failed',
        error: '执行失败',
        recoverable: true,
        summary: '',
        runDir: '/tmp/run-2',
        returnedToApp: false,
        result: businessResult
      };

      let response: MobileGuiTaskToolResponse = mobileGuiTaskToolResponseFromRunResult(result);
      let payload = parseJsonCompat<TestPayload>(stringifyMobileGuiTaskToolResponse(response));

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('failed');
      expect(payload.result === undefined).assertTrue();
    });

    it('omitsBusinessResultFromCancelledWirePayload', 0, () => {
      let keyValues: Record<string, MobileGuiTaskJsonValue> = {};
      keyValues['stale'] = true;
      let items: Object[] = [];
      let businessResult: MobileGuiTaskBusinessResult = {
        outcome: 'empty',
        summary: '陈旧取消结果',
        key_values: keyValues,
        items: items
      };
      let result: MobileGuiTaskRunResult = {
        ok: false,
        status: 'cancelled',
        errorCode: 'user_cancelled',
        error: '用户取消',
        recoverable: true,
        summary: '',
        runDir: '/tmp/run-cancelled',
        returnedToApp: true,
        result: businessResult
      };

      let response: MobileGuiTaskToolResponse = mobileGuiTaskToolResponseFromRunResult(result);
      let payload = parseJsonCompat<TestPayload>(stringifyMobileGuiTaskToolResponse(response));

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('cancelled');
      expect(payload.result === undefined).assertTrue();
    });

    it('returnsUnavailableWhenCallbacksMissing', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContext());
      let payload = parseJsonCompat<TestPayload>(output);

      expect(payload.ok).assertFalse();
      expect(payload.error_code).assertEqual('unavailable');
      expect(payload.recoverable).assertTrue();
      expect(payload.status).assertEqual('unavailable');
    });

    it('returnsUnavailableWhenRunCallbackMissing', 0, async () => {
      let confirmCalls = 0;
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          confirmCalls++;
          return true;
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(confirmCalls).assertEqual(0);
      expect(payload.ok).assertFalse();
      expect(payload.error_code).assertEqual('unavailable');
      expect(payload.recoverable).assertTrue();
      expect(payload.status).assertEqual('unavailable');
    });

    it('returnsUnavailableWhenConfirmCallbackMissing', 0, async () => {
      let runCalls = 0;
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          runCalls++;
          return {
            ok: true,
            status: 'success',
            errorCode: '',
            error: '',
            recoverable: false,
            summary: '',
            runDir: '',
            returnedToApp: false
          };
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(runCalls).assertEqual(0);
      expect(payload.ok).assertFalse();
      expect(payload.error_code).assertEqual('unavailable');
      expect(payload.recoverable).assertTrue();
      expect(payload.status).assertEqual('unavailable');
    });

    it('returnsRejectedWhenUserDoesNotConfirm', 0, async () => {
      let confirmCalls = 0;
      let runCalls = 0;
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          confirmCalls++;
          return false;
        },
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          runCalls++;
          return {
            ok: true,
            status: 'success',
            errorCode: '',
            error: '',
            recoverable: false,
            summary: '',
            runDir: '',
            returnedToApp: false
          };
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(confirmCalls).assertEqual(1);
      expect(runCalls).assertEqual(0);
      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('rejected');
      expect(payload.error_code).assertEqual('user_rejected');
      expect(payload.recoverable).assertTrue();
    });

    it('returnsRunResultWhenConfirmed', 0, async () => {
      let confirmedTask = '';
      let runTask = '';
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信","max_steps":7}',
        testContextWithCallbacks({
          confirmMobileGuiTask: async (request: MobileGuiTaskRequest): Promise<boolean> => {
            confirmedTask = request.task;
            return true;
          },
          runMobileGuiTask: async (request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
            runTask = request.task;
            return {
              ok: true,
              status: 'success',
              errorCode: '',
              error: '',
              recoverable: false,
              summary: '已完成',
              runDir: '/tmp/run-3',
              returnedToApp: true
            };
          }
        }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(confirmedTask).assertEqual('打开微信');
      expect(runTask).assertEqual('打开微信');
      expect(payload.ok).assertTrue();
      expect(payload.status).assertEqual('success');
      expect(payload.summary).assertEqual('已完成');
      expect(payload.run_dir).assertEqual('/tmp/run-3');
      expect(payload.returned_to_app).assertTrue();
    });

    it('returnsStableFailureFromRunner', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          return true;
        },
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          return {
            ok: false,
            status: 'failed',
            errorCode: 'tool_failed',
            error: '执行失败',
            recoverable: true,
            summary: '',
            runDir: '/tmp/run-4',
            returnedToApp: false
          };
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('failed');
      expect(payload.error_code).assertEqual('tool_failed');
      expect(payload.error).assertEqual('执行失败');
      expect(payload.recoverable).assertTrue();
    });

    it('returnsStructuredFailureWhenConfirmationThrows', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          throw new Error('confirm exploded');
        },
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          throw new Error('run should not execute');
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('failed');
      expect(payload.error_code).assertEqual('workflow_failed');
      expect(payload.recoverable).assertTrue();
      expect(payload.error !== undefined && payload.error!.indexOf('confirm exploded') >= 0).assertTrue();
    });

    it('returnsCancelledWhenConfirmationDialogIsDismissed', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          throw createMobileGuiTaskConfirmationCancelledError('用户关闭确认弹窗');
        },
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          throw new Error('run should not execute');
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(isMobileGuiTaskConfirmationCancelledError(
        createMobileGuiTaskConfirmationCancelledError('用户关闭确认弹窗'))).assertTrue();
      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('cancelled');
      expect(payload.error_code).assertEqual('user_cancelled');
      expect(payload.recoverable).assertTrue();
      expect(payload.error !== undefined && payload.error!.indexOf('用户关闭确认弹窗') >= 0).assertTrue();
    });

    it('returnsStructuredFailureWhenRunnerThrows', 0, async () => {
      let tool = createMobileGuiTaskTool();
      let output = await tool.execute('{"task":"打开微信"}', testContextWithCallbacks({
        confirmMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<boolean> => {
          return true;
        },
        runMobileGuiTask: async (_request: MobileGuiTaskRequest): Promise<MobileGuiTaskRunResult> => {
          throw new Error('runner exploded');
        }
      }));
      let payload = parseJsonCompat<TestPayload>(output);

      expect(payload.ok).assertFalse();
      expect(payload.status).assertEqual('failed');
      expect(payload.error_code).assertEqual('workflow_failed');
      expect(payload.recoverable).assertTrue();
      expect(payload.error !== undefined && payload.error!.indexOf('runner exploded') >= 0).assertTrue();
    });
  });
}
