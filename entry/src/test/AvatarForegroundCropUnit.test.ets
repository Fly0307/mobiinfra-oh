import { describe, it, expect } from '@ohos/hypium';
import {
  AvatarAlphaCropBounds,
  AvatarCroppedRgba,
  cropRgbaToAlphaBounds,
  findAlphaCropBounds
} from '../main/ets/datamanager/avatar/AvatarForegroundCrop';

function setPixel(buffer: Uint8Array, width: number, x: number, y: number, r: number, g: number, b: number,
  a: number): void {
  let offset = (y * width + x) * 4;
  buffer[offset] = r;
  buffer[offset + 1] = g;
  buffer[offset + 2] = b;
  buffer[offset + 3] = a;
}

export default function avatarForegroundCropUnitTest() {
  describe('avatarForegroundCropUnitTest', () => {
    it('findsTightAlphaBounds', 0, () => {
      let pixels = new Uint8Array(5 * 4 * 4);
      setPixel(pixels, 5, 1, 1, 10, 20, 30, 255);
      setPixel(pixels, 5, 3, 2, 40, 50, 60, 128);
      setPixel(pixels, 5, 2, 3, 70, 80, 90, 1);

      let bounds: AvatarAlphaCropBounds = findAlphaCropBounds(pixels, 5, 4, 0);

      expect(bounds.isEmpty).assertFalse();
      expect(bounds.left).assertEqual(1);
      expect(bounds.top).assertEqual(1);
      expect(bounds.width).assertEqual(3);
      expect(bounds.height).assertEqual(3);
    });

    it('returnsEmptyBoundsForTransparentImage', 0, () => {
      let pixels = new Uint8Array(4 * 3 * 4);

      let bounds: AvatarAlphaCropBounds = findAlphaCropBounds(pixels, 4, 3, 0);

      expect(bounds.isEmpty).assertTrue();
      expect(bounds.width).assertEqual(0);
      expect(bounds.height).assertEqual(0);
    });

    it('copiesOnlyPixelsInsideAlphaBounds', 0, () => {
      let pixels = new Uint8Array(4 * 3 * 4);
      setPixel(pixels, 4, 1, 1, 11, 12, 13, 255);
      setPixel(pixels, 4, 2, 1, 21, 22, 23, 128);
      setPixel(pixels, 4, 1, 2, 31, 32, 33, 64);
      setPixel(pixels, 4, 2, 2, 41, 42, 43, 32);

      let bounds: AvatarAlphaCropBounds = findAlphaCropBounds(pixels, 4, 3, 0);
      let cropped: AvatarCroppedRgba = cropRgbaToAlphaBounds(pixels, 4, bounds);

      expect(cropped.width).assertEqual(2);
      expect(cropped.height).assertEqual(2);
      expect(cropped.pixels.length).assertEqual(16);
      expect(cropped.pixels[0]).assertEqual(11);
      expect(cropped.pixels[4]).assertEqual(21);
      expect(cropped.pixels[8]).assertEqual(31);
      expect(cropped.pixels[12]).assertEqual(41);
      expect(cropped.pixels[15]).assertEqual(32);
    });
  });
}
