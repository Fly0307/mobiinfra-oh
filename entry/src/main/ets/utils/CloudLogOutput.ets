// 云端日志输出统一处理追加、聚焦重置和最大长度裁剪，避免设置页测试结果被历史日志淹没。
export function buildCloudOutputLog(currentOutput: string, line: string, replaceExisting: boolean,
  maxLength: number): string {
  let nextLogs = replaceExisting || currentOutput.length === 0 ? line : currentOutput + '\n' + line;
  if (maxLength > 0 && nextLogs.length > maxLength) {
    nextLogs = nextLogs.substring(nextLogs.length - maxLength);
  }
  return nextLogs;
}
