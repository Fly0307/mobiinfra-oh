export interface Pcm16WavOptions {
  sampleRate: number;
  channels: number;
}

const PCM16_BITS_PER_SAMPLE: number = 16;
const WAV_HEADER_BYTES: number = 44;

export function concatPcmChunks(chunks: Uint8Array[]): Uint8Array {
  let totalLength = 0;
  for (let index = 0; index < chunks.length; index++) {
    totalLength += chunks[index].byteLength;
  }
  let output = new Uint8Array(totalLength);
  let offset = 0;
  for (let index = 0; index < chunks.length; index++) {
    let chunk = chunks[index];
    for (let byteIndex = 0; byteIndex < chunk.byteLength; byteIndex++) {
      output[offset + byteIndex] = chunk[byteIndex];
    }
    offset += chunk.byteLength;
  }
  return output;
}

export function buildPcm16WavBytes(pcm: Uint8Array, options: Pcm16WavOptions): Uint8Array {
  // MiMO 流式 TTS 返回裸 PCM16LE，缓存复播需要补标准 RIFF/WAVE 头后交给 AVPlayer。
  let channels = Math.max(1, options.channels);
  let sampleRate = Math.max(1, options.sampleRate);
  let byteRate = sampleRate * channels * PCM16_BITS_PER_SAMPLE / 8;
  let blockAlign = channels * PCM16_BITS_PER_SAMPLE / 8;
  let output = new Uint8Array(WAV_HEADER_BYTES + pcm.byteLength);
  writeAscii(output, 0, 'RIFF');
  writeLe32(output, 4, 36 + pcm.byteLength);
  writeAscii(output, 8, 'WAVE');
  writeAscii(output, 12, 'fmt ');
  writeLe32(output, 16, 16);
  writeLe16(output, 20, 1);
  writeLe16(output, 22, channels);
  writeLe32(output, 24, sampleRate);
  writeLe32(output, 28, byteRate);
  writeLe16(output, 32, blockAlign);
  writeLe16(output, 34, PCM16_BITS_PER_SAMPLE);
  writeAscii(output, 36, 'data');
  writeLe32(output, 40, pcm.byteLength);
  for (let index = 0; index < pcm.byteLength; index++) {
    output[WAV_HEADER_BYTES + index] = pcm[index];
  }
  return output;
}

function writeAscii(bytes: Uint8Array, offset: number, value: string): void {
  for (let index = 0; index < value.length; index++) {
    bytes[offset + index] = value.charCodeAt(index);
  }
}

function writeLe16(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
}

function writeLe32(bytes: Uint8Array, offset: number, value: number): void {
  bytes[offset] = value & 0xFF;
  bytes[offset + 1] = (value >> 8) & 0xFF;
  bytes[offset + 2] = (value >> 16) & 0xFF;
  bytes[offset + 3] = (value >> 24) & 0xFF;
}
