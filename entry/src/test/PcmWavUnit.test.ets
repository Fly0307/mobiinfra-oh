import { describe, it, expect } from '@ohos/hypium';
import { buildPcm16WavBytes, concatPcmChunks } from '../main/ets/utils/voice/PcmWav';

function readAscii(bytes: Uint8Array, start: number, length: number): string {
  let chars: string[] = [];
  for (let index = 0; index < length; index++) {
    chars.push(String.fromCharCode(bytes[start + index]));
  }
  return chars.join('');
}

function readLe32(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
}

function readLe16(bytes: Uint8Array, offset: number): number {
  return bytes[offset] | (bytes[offset + 1] << 8);
}

export default function pcmWavUnitTest() {
  describe('pcmWavUnitTest', () => {
    it('concatsPcmChunksWithoutSharingMutableInput', 0, () => {
      let first = new Uint8Array([1, 2]);
      let second = new Uint8Array([3, 4, 5]);
      let pcm = concatPcmChunks([first, second]);

      first[0] = 9;

      expect(pcm.length).assertEqual(5);
      expect(pcm[0]).assertEqual(1);
      expect(pcm[4]).assertEqual(5);
    });

    it('wrapsPcm16Mono24kDataInWavHeader', 0, () => {
      let wav = buildPcm16WavBytes(new Uint8Array([1, 2, 3, 4]), {
        sampleRate: 24000,
        channels: 1
      });

      expect(wav.length).assertEqual(48);
      expect(readAscii(wav, 0, 4)).assertEqual('RIFF');
      expect(readAscii(wav, 8, 4)).assertEqual('WAVE');
      expect(readAscii(wav, 12, 4)).assertEqual('fmt ');
      expect(readAscii(wav, 36, 4)).assertEqual('data');
      expect(readLe32(wav, 24)).assertEqual(24000);
      expect(readLe32(wav, 28)).assertEqual(48000);
      expect(readLe16(wav, 22)).assertEqual(1);
      expect(readLe16(wav, 34)).assertEqual(16);
      expect(readLe32(wav, 40)).assertEqual(4);
      expect(wav[44]).assertEqual(1);
      expect(wav[47]).assertEqual(4);
    });
  });
}
