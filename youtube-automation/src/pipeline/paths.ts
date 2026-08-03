import { mkdir } from "node:fs/promises";
import path from "node:path";
import { PipelinePaths } from "../types.js";

const OUTPUT_ROOT = path.resolve(process.cwd(), "output");

export async function pathsFor(topicSlug: string): Promise<PipelinePaths> {
  const root = path.join(OUTPUT_ROOT, topicSlug);
  const paths: PipelinePaths = {
    root,
    scriptFile: path.join(root, "script.json"),
    audioDir: path.join(root, "audio"),
    scenesDir: path.join(root, "scenes"),
    finalVideo: path.join(root, "final.mp4"),
    thumbnail: path.join(root, "thumbnail.jpg"),
  };

  await mkdir(paths.audioDir, { recursive: true });
  await mkdir(paths.scenesDir, { recursive: true });

  return paths;
}
