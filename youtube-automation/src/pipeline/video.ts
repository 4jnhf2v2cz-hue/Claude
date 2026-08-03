import path from "node:path";
import { access } from "node:fs/promises";
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

async function fileExists(p: string): Promise<boolean> {
  try {
    await access(p);
    return true;
  } catch {
    return false;
  }
}

/**
 * Returns the list of per-scene video clip paths, in scene order.
 *
 * `onlySceneNumber` generates just that one scene (useful for spending
 * real generation credit a scene at a time instead of all at once).
 * Scenes whose clip file already exists on disk are skipped rather than
 * regenerated, so re-running this command never re-spends credit on a
 * scene you already have.
 */
export async function runVideoStep(
  script: Script,
  forceMock: boolean,
  onlySceneNumber?: number
): Promise<string[]> {
  const generator = getVideoGenerator(forceMock);
  const paths = await pathsFor(script.topicSlug);
  const clipFiles: string[] = [];

  const scenes = onlySceneNumber
    ? script.scenes.filter((s) => s.sceneNumber === onlySceneNumber)
    : script.scenes;

  if (onlySceneNumber && scenes.length === 0) {
    throw new Error(
      `Scene ${onlySceneNumber} not found (script has ${script.scenes.length} scenes)`
    );
  }

  for (const scene of scenes) {
    const outPath = path.join(paths.scenesDir, `scene-${scene.sceneNumber}.mp4`);

    if (await fileExists(outPath)) {
      console.log(`[video] Scene ${scene.sceneNumber} already exists -> ${outPath} (skipped)`);
      clipFiles.push(outPath);
      continue;
    }

    await generator.generateScene(scene.visualPrompt, scene.durationSeconds, outPath);
    clipFiles.push(outPath);
    console.log(`[video] Scene ${scene.sceneNumber} -> ${outPath}`);
  }

  return clipFiles;
}
