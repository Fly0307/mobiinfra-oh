import { describe, it, expect } from '@ohos/hypium';
import {
  AvatarAlphaCropBounds,
  AvatarCroppedRgba,
  cropRgbaToAlphaBounds,
  findAlphaCropBounds
} from '../main/ets/datamanager/avatar/AvatarForegroundCrop';
import {
  AVATAR_MESSAGE_FOREGROUND_HEIGHT,
  AVATAR_MESSAGE_FOREGROUND_WIDTH,
  AvatarForegroundContainLayout,
  AvatarForegroundThumbnailRgba,
  createAvatarForegroundMessageRgba,
  computeAvatarForegroundContainLayout
} from '../main/ets/datamanager/avatar/AvatarForegroundThumbnail';

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

    it('messageForegroundContainLayoutKeepsWideImageAspectRatio', 0, () => {
      let layout: AvatarForegroundContainLayout =
        computeAvatarForegroundContainLayout(400, 200, AVATAR_MESSAGE_FOREGROUND_WIDTH, AVATAR_MESSAGE_FOREGROUND_HEIGHT);

      expect(layout.targetWidth).assertEqual(168);
      expect(layout.targetHeight).assertEqual(84);
      expect(layout.offsetX).assertEqual(0);
      expect(layout.offsetY).assertEqual(66);
      expect(layout.scaleX).assertEqual(layout.scaleY);
    });

    it('messageForegroundContainLayoutKeepsTallImageAspectRatio', 0, () => {
      let layout: AvatarForegroundContainLayout =
        computeAvatarForegroundContainLayout(100, 300, AVATAR_MESSAGE_FOREGROUND_WIDTH, AVATAR_MESSAGE_FOREGROUND_HEIGHT);

      expect(layout.targetWidth).assertEqual(72);
      expect(layout.targetHeight).assertEqual(216);
      expect(layout.offsetX).assertEqual(48);
      expect(layout.offsetY).assertEqual(0);
      expect(layout.scaleX).assertEqual(layout.scaleY);
    });

    it('messageForegroundRgbaCentersScaledPixelsWithTransparentPadding', 0, () => {
      let pixels = new Uint8Array(2 * 1 * 4);
      setPixel(pixels, 2, 0, 0, 10, 20, 30, 128);
      setPixel(pixels, 2, 1, 0, 40, 50, 60, 255);

      let thumbnail: AvatarForegroundThumbnailRgba = createAvatarForegroundMessageRgba(pixels, 2, 1, 8, 4, 4);

      expect(thumbnail.width).assertEqual(4);
      expect(thumbnail.height).assertEqual(4);
      expect(thumbnail.pixels[3]).assertEqual(0);
      let firstDrawnOffset: number = (1 * 4 + 0) * 4;
      let secondDrawnOffset: number = (1 * 4 + 2) * 4;
      expect(thumbnail.pixels[firstDrawnOffset]).assertEqual(10);
      expect(thumbnail.pixels[firstDrawnOffset + 3]).assertEqual(128);
      expect(thumbnail.pixels[secondDrawnOffset]).assertEqual(40);
      expect(thumbnail.pixels[secondDrawnOffset + 3]).assertEqual(255);
    });
  });
}
