import path from "node:path";
import { Script } from "../types.js";
import { TextToSpeech } from "../providers/tts/types.js";
import { ElevenLabsTts } from "../providers/tts/elevenlabs.js";
import { MockTts } from "../providers/tts/mock.js";
import { pathsFor } from "./paths.js";

export function getTts(forceMock: boolean): TextToSpeech {
  const apiKey = process.env.ELEVENLABS_API_KEY;
  const voiceId = process.env.ELEVENLABS_VOICE_ID;
  if (!forceMock && apiKey && voiceId) {
    return new ElevenLabsTts(apiKey, voiceId);
  }
  console.log("[voice] No ElevenLabs credentials (or --dry-run) — using mock silent audio");
  return new MockTts();
}

/** Returns the list of per-scene audio file paths, in scene order. */
export async function runVoiceStep(
  script: Script,
  forceMock: boolean
): Promise<string[]> {
  const tts = getTts(forceMock);
  const paths = await pathsFor(script.topicSlug);
  const audioFiles: string[] = [];

  for (const scene of script.scenes) {
    const outPath = path.join(
      paths.audioDir,
      `scene-${scene.sceneNumber}.${tts.fileExtension}`
    );
    await tts.synthesize(scene.captionText, outPath);
    audioFiles.push(outPath);
    console.log(`[voice] Scene ${scene.sceneNumber} -> ${outPath}`);
  }

  return audioFiles;
}
