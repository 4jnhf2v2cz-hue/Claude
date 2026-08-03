import { writeFile } from "node:fs/promises";
import { TextToSpeech } from "./types.js";
import { estimateDurationSeconds } from "../../util/duration.js";

const SAMPLE_RATE = 22050;

/**
 * No-API-key stand-in: writes a silent WAV of a duration estimated from word
 * count, so downstream steps (assembly) have a real audio file to sync
 * against. Swap in ElevenLabsTts once ELEVENLABS_API_KEY is set for actual
 * narration/singing.
 */
export class MockTts implements TextToSpeech {
  readonly fileExtension = "wav";

  async synthesize(text: string, outPath: string): Promise<void> {
    const seconds = estimateDurationSeconds(text);
    const buffer = buildSilentWav(seconds, SAMPLE_RATE);
    await writeFile(outPath, buffer);
  }
}

function buildSilentWav(durationSeconds: number, sampleRate: number): Buffer {
  const numSamples = durationSeconds * sampleRate;
  const dataSize = numSamples * 2; // 16-bit mono
  const buffer = Buffer.alloc(44 + dataSize);

  buffer.write("RIFF", 0);
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8);
  buffer.write("fmt ", 12);
  buffer.writeUInt32LE(16, 16); // PCM chunk size
  buffer.writeUInt16LE(1, 20); // PCM format
  buffer.writeUInt16LE(1, 22); // mono
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * 2, 28); // byte rate
  buffer.writeUInt16LE(2, 32); // block align
  buffer.writeUInt16LE(16, 34); // bits per sample
  buffer.write("data", 36);
  buffer.writeUInt32LE(dataSize, 40);
  // remaining bytes are already zero (silence)

  return buffer;
}
