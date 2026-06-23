export const AVATAR_MESSAGE_FOREGROUND_WIDTH: number = 168;
export const AVATAR_MESSAGE_FOREGROUND_HEIGHT: number = 216;

export interface AvatarForegroundContainLayout {
  targetWidth: number;
  targetHeight: number;
  offsetX: number;
  offsetY: number;
  scaleX: number;
  scaleY: number;
}

export interface AvatarForegroundThumbnailRgba {
  width: number;
  height: number;
  buffer: ArrayBuffer;
  pixels: Uint8Array;
}

const PNG_SIGNATURE: number[] = [137, 80, 78, 71, 13, 10, 26, 10];
const PNG_CHUNK_IHDR: string = 'IHDR';
const PNG_CHUNK_IDAT: string = 'IDAT';
const PNG_CHUNK_IEND: string = 'IEND';
const ZLIB_STORE_HEADER: number[] = [0x78, 0x01];
const DEFLATE_STORE_BLOCK_MAX_LENGTH: number = 65535;

function emptyContainLayout(): AvatarForegroundContainLayout {
  return {
    targetWidth: 0,
    targetHeight: 0,
    offsetX: 0,
    offsetY: 0,
    scaleX: 0,
    scaleY: 0
  };
}

// 聊天气泡头像缓存固定为 168x216。这里先计算 contain 布局，后续绘制只使用
// 同一个缩放比例采样，确保人物前景保持原始比例，不会被横向或纵向拉伸。
export function computeAvatarForegroundContainLayout(sourceWidth: number, sourceHeight: number,
  canvasWidth: number, canvasHeight: number): AvatarForegroundContainLayout {
  if (sourceWidth <= 0 || sourceHeight <= 0 || canvasWidth <= 0 || canvasHeight <= 0) {
    return emptyContainLayout();
  }
  let scale: number = Math.min(canvasWidth / sourceWidth, canvasHeight / sourceHeight);
  let targetWidth: number = Math.max(1, Math.round(sourceWidth * scale));
  let targetHeight: number = Math.max(1, Math.round(sourceHeight * scale));
  return {
    targetWidth: targetWidth,
    targetHeight: targetHeight,
    offsetX: Math.floor((canvasWidth - targetWidth) / 2),
    offsetY: Math.floor((canvasHeight - targetHeight) / 2),
    scaleX: scale,
    scaleY: scale
  };
}

export function createAvatarForegroundMessageRgba(sourcePixels: Uint8Array, sourceWidth: number,
  sourceHeight: number, sourceStride: number = sourceWidth * 4,
  canvasWidth: number = AVATAR_MESSAGE_FOREGROUND_WIDTH,
  canvasHeight: number = AVATAR_MESSAGE_FOREGROUND_HEIGHT): AvatarForegroundThumbnailRgba {
  let targetBuffer: ArrayBuffer = new ArrayBuffer(canvasWidth * canvasHeight * 4);
  let targetPixels: Uint8Array = new Uint8Array(targetBuffer);
  let layout: AvatarForegroundContainLayout =
    computeAvatarForegroundContainLayout(sourceWidth, sourceHeight, canvasWidth, canvasHeight);
  if (layout.targetWidth <= 0 || layout.targetHeight <= 0 || sourceStride < sourceWidth * 4 ||
    sourcePixels.length < sourceStride * sourceHeight) {
    return {
      width: canvasWidth,
      height: canvasHeight,
      buffer: targetBuffer,
      pixels: targetPixels
    };
  }

  for (let targetY: number = 0; targetY < layout.targetHeight; targetY++) {
    let sourceY: number = Math.floor(targetY / layout.scaleY);
    if (sourceY >= sourceHeight) {
      sourceY = sourceHeight - 1;
    }
    for (let targetX: number = 0; targetX < layout.targetWidth; targetX++) {
      let sourceX: number = Math.floor(targetX / layout.scaleX);
      if (sourceX >= sourceWidth) {
        sourceX = sourceWidth - 1;
      }
      let sourceOffset: number = sourceY * sourceStride + sourceX * 4;
      let canvasX: number = layout.offsetX + targetX;
      let canvasY: number = layout.offsetY + targetY;
      let targetOffset: number = (canvasY * canvasWidth + canvasX) * 4;
      targetPixels[targetOffset] = sourcePixels[sourceOffset];
      targetPixels[targetOffset + 1] = sourcePixels[sourceOffset + 1];
      targetPixels[targetOffset + 2] = sourcePixels[sourceOffset + 2];
      targetPixels[targetOffset + 3] = sourcePixels[sourceOffset + 3];
    }
  }

  return {
    width: canvasWidth,
    height: canvasHeight,
    buffer: targetBuffer,
    pixels: targetPixels
  };
}

function writeUint32Be(buffer: Uint8Array, offset: number, value: number): void {
  let normalized = value >>> 0;
  buffer[offset] = (normalized >>> 24) & 0xFF;
  buffer[offset + 1] = (normalized >>> 16) & 0xFF;
  buffer[offset + 2] = (normalized >>> 8) & 0xFF;
  buffer[offset + 3] = normalized & 0xFF;
}

function writeUint16Le(buffer: Uint8Array, offset: number, value: number): void {
  buffer[offset] = value & 0xFF;
  buffer[offset + 1] = (value >>> 8) & 0xFF;
}

function asciiBytes(text: string): Uint8Array {
  let bytes = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    bytes[i] = text.charCodeAt(i) & 0xFF;
  }
  return bytes;
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (let part of parts) {
    total += part.length;
  }
  let result = new Uint8Array(total);
  let offset = 0;
  for (let part of parts) {
    result.set(part, offset);
    offset += part.length;
  }
  return result;
}

function crc32(bytes: Uint8Array): number {
  let crc = 0xFFFFFFFF;
  for (let i = 0; i < bytes.length; i++) {
    crc = (crc ^ bytes[i]) >>> 0;
    for (let bit = 0; bit < 8; bit++) {
      let mask = -(crc & 1);
      crc = ((crc >>> 1) ^ (0xEDB88320 & mask)) >>> 0;
    }
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}

function adler32(bytes: Uint8Array): number {
  let a = 1;
  let b = 0;
  for (let i = 0; i < bytes.length; i++) {
    a = (a + bytes[i]) % 65521;
    b = (b + a) % 65521;
  }
  return (((b << 16) >>> 0) | a) >>> 0;
}

function pngChunk(type: string, data: Uint8Array): Uint8Array {
  let typeBytes = asciiBytes(type);
  let chunk = new Uint8Array(12 + data.length);
  writeUint32Be(chunk, 0, data.length);
  chunk.set(typeBytes, 4);
  chunk.set(data, 8);
  let crcInput = new Uint8Array(typeBytes.length + data.length);
  crcInput.set(typeBytes, 0);
  crcInput.set(data, typeBytes.length);
  writeUint32Be(chunk, 8 + data.length, crc32(crcInput));
  return chunk;
}

function zlibStore(bytes: Uint8Array): Uint8Array {
  let blockCount = Math.max(1, Math.ceil(bytes.length / DEFLATE_STORE_BLOCK_MAX_LENGTH));
  let result = new Uint8Array(ZLIB_STORE_HEADER.length + bytes.length + blockCount * 5 + 4);
  result[0] = ZLIB_STORE_HEADER[0];
  result[1] = ZLIB_STORE_HEADER[1];
  let sourceOffset = 0;
  let targetOffset = ZLIB_STORE_HEADER.length;
  for (let blockIndex = 0; blockIndex < blockCount; blockIndex++) {
    let remaining = bytes.length - sourceOffset;
    let blockLength = Math.min(DEFLATE_STORE_BLOCK_MAX_LENGTH, remaining);
    let finalBlock = blockIndex === blockCount - 1;
    result[targetOffset] = finalBlock ? 0x01 : 0x00;
    writeUint16Le(result, targetOffset + 1, blockLength);
    writeUint16Le(result, targetOffset + 3, (~blockLength) & 0xFFFF);
    targetOffset += 5;
    if (blockLength > 0) {
      result.set(bytes.subarray(sourceOffset, sourceOffset + blockLength), targetOffset);
      sourceOffset += blockLength;
      targetOffset += blockLength;
    }
  }
  writeUint32Be(result, targetOffset, adler32(bytes));
  return result;
}

export function encodeRgbaToPng(pixels: Uint8Array, width: number, height: number): Uint8Array {
  let rowBytes = width * 4;
  let scanline = new Uint8Array((rowBytes + 1) * height);
  for (let y = 0; y < height; y++) {
    let scanlineOffset = y * (rowBytes + 1);
    scanline[scanlineOffset] = 0;
    scanline.set(pixels.subarray(y * rowBytes, y * rowBytes + rowBytes), scanlineOffset + 1);
  }
  let ihdr = new Uint8Array(13);
  writeUint32Be(ihdr, 0, width);
  writeUint32Be(ihdr, 4, height);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;
  return concatBytes([
    new Uint8Array(PNG_SIGNATURE),
    pngChunk(PNG_CHUNK_IHDR, ihdr),
    pngChunk(PNG_CHUNK_IDAT, zlibStore(scanline)),
    pngChunk(PNG_CHUNK_IEND, new Uint8Array(0))
  ]);
}

export function encodeAvatarForegroundMessagePng(thumbnail: AvatarForegroundThumbnailRgba): Uint8Array {
  return encodeRgbaToPng(thumbnail.pixels, thumbnail.width, thumbnail.height);
}
