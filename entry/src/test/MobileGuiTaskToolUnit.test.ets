import { describe, it, expect } from '@ohos/hypium';
import {
  MOBILE_GUI_TASK_TOOL_NAME,
  createMobileGuiTaskTool,
  mobileGuiTaskToolParameters,
  normalizeMobileGuiTaskArguments
} from '../main/ets/utils/MobileGuiTaskTool';

interface TestSchemaObject {
  type?: string;
  additionalProperties?: boolean;
  required?: string[];
  properties?: Record<string, Object>;
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

    it('fallsBackToDefaultMaxStepsForNegativeValues', 0, () => {
      let validation = normalizeMobileGuiTaskArguments('{"task":"打开微信","max_steps":-1}');

      expect(validation.ok).assertTrue();
      expect(validation.request.maxSteps).assertEqual(20);
    });
  });
}
