const SENSITIVE_MASK_MARKER: string = '•';

// 统一识别设置页生成的遮罩值，避免历史遮罩串被继续当作真实密钥使用。
export function isMaskedSensitiveValue(value: string): boolean {
  let normalized = value.trim();
  if (normalized.length === 0) {
    return false;
  }
  return normalized.indexOf(SENSITIVE_MASK_MARKER) >= 0;
}
