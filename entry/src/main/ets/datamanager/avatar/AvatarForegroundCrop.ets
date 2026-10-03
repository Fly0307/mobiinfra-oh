export interface AvatarAlphaCropBounds {
  left: number;
  top: number;
  width: number;
  height: number;
  isEmpty: boolean;
}

export interface AvatarCroppedRgba {
  width: number;
  height: number;
  buffer: ArrayBuffer;
  pixels: Uint8Array;
}

function emptyAlphaCropBounds(): AvatarAlphaCropBounds {
  return {
    left: 0,
    top: 0,
    width: 0,
    height: 0,
    isEmpty: true
  };
}

// subjectSegmentation 生成的前景图可能仍保留原图尺寸的透明画布。
// 保存 PNG 前先按 alpha 通道寻找非透明外接矩形，能让聊天页数字人紧贴真实人物区域显示。
export function findAlphaCropBounds(pixels: Uint8Array, width: number, height: number,
  alphaThreshold: number, sourceStride: number = width * 4): AvatarAlphaCropBounds {
  if (width <= 0 || height <= 0 || sourceStride < width * 4 || pixels.length < sourceStride * height) {
    return emptyAlphaCropBounds();
  }
  let left: number = width;
  let top: number = height;
  let right: number = -1;
  let bottom: number = -1;
  for (let y: number = 0; y < height; y++) {
    for (let x: number = 0; x < width; x++) {
      let alphaOffset: number = y * sourceStride + x * 4 + 3;
      if (pixels[alphaOffset] > alphaThreshold) {
        if (x < left) {
          left = x;
        }
        if (x > right) {
          right = x;
        }
        if (y < top) {
          top = y;
        }
        if (y > bottom) {
          bottom = y;
        }
      }
    }
  }
  if (right < left || bottom < top) {
    return emptyAlphaCropBounds();
  }
  return {
    left: left,
    top: top,
    width: right - left + 1,
    height: bottom - top + 1,
    isEmpty: false
  };
}

export function cropRgbaToAlphaBounds(pixels: Uint8Array, sourceWidth: number,
  bounds: AvatarAlphaCropBounds, sourceStride: number = sourceWidth * 4): AvatarCroppedRgba {
  if (bounds.isEmpty || bounds.width <= 0 || bounds.height <= 0 || sourceWidth <= 0 ||
    sourceStride < sourceWidth * 4) {
    let emptyBuffer: ArrayBuffer = new ArrayBuffer(0);
    return {
      width: 0,
      height: 0,
      buffer: emptyBuffer,
      pixels: new Uint8Array(emptyBuffer)
    };
  }
  let targetByteCount: number = bounds.width * bounds.height * 4;
  let targetBuffer: ArrayBuffer = new ArrayBuffer(targetByteCount);
  let targetPixels: Uint8Array = new Uint8Array(targetBuffer);
  for (let y: number = 0; y < bounds.height; y++) {
    for (let x: number = 0; x < bounds.width; x++) {
      let sourceOffset: number = (bounds.top + y) * sourceStride + (bounds.left + x) * 4;
      let targetOffset: number = (y * bounds.width + x) * 4;
      targetPixels[targetOffset] = pixels[sourceOffset];
      targetPixels[targetOffset + 1] = pixels[sourceOffset + 1];
      targetPixels[targetOffset + 2] = pixels[sourceOffset + 2];
      targetPixels[targetOffset + 3] = pixels[sourceOffset + 3];
    }
  }
  return {
    width: bounds.width,
    height: bounds.height,
    buffer: targetBuffer,
    pixels: targetPixels
  };
}
