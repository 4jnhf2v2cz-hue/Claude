import path from "node:path";
import { Script } from "../types.js";
import { VideoGenerator } from "../providers/videoGen/types.js";
import { HiggsfieldVideoGenerator } from "../providers/videoGen/higgsfield.js";
import { MockVideoGenerator } from "../providers/videoGen/mock.js";
import { pathsFor } from "./paths.js";

export function getVideoGenerator(forceMock: boolean): VideoGenerator {
  const keyId = process.env.HIGGSFIELD_KEY_ID;
  const keySecret = process.env.HIGGSFIELD_KEY_SECRET;
  const endpoint = process.env.HIGGSFIELD_ENDPOINT ?? "/v1/image2video/dop";
  if (!forceMock && keyId && keySecret) {
    return new HiggsfieldVideoGenerator(keyId, keySecret, endpoint);
  }
  console.log(
    "[video] No HIGGSFIELD_KEY_ID/HIGGSFIELD_KEY_SECRET (or --dry-run) — using mock placeholder clips"
  );
  return new MockVideoGenerator();
}

/** Returns the list of per-scene video clip paths, in scene order. */
export async function runVideoStep(
  script: Script,
  forceMock: boolean
): Promise<string[]> {
  const generator = getVideoGenerator(forceMock);
  const paths = await pathsFor(script.topicSlug);
  const clipFiles: string[] = [];

  for (const scene of script.scenes) {
    const outPath = path.join(paths.scenesDir, `scene-${scene.sceneNumber}.mp4`);
    await generator.generateScene(scene.visualPrompt, scene.durationSeconds, outPath);
    clipFiles.push(outPath);
    console.log(`[video] Scene ${scene.sceneNumber} -> ${outPath}`);
  }

  return clipFiles;
}
