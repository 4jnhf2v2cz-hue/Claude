import { writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { Script } from "../types.js";
import { pathsFor } from "./paths.js";
import { runFfmpeg } from "../util/ffmpeg.js";

/**
 * Concatenates per-scene video clips and per-scene audio clips into one
 * final video, burning each scene's caption text in as it plays. Assumes
 * scene N's video and audio clips have matching durations (true for mock
 * providers by construction; for real providers, tune scene.durationSeconds
 * / regenerate a scene if drift is noticeable).
 */
export async function runAssembleStep(
  script: Script,
  videoClips: string[],
  audioClips: string[]
): Promise<string> {
  const paths = await pathsFor(script.topicSlug);

  const videoListFile = path.join(paths.root, "video-concat.txt");
  const audioListFile = path.join(paths.root, "audio-concat.txt");
  const captionedDir = path.join(paths.scenesDir, "captioned");
  await mkdir(captionedDir, { recursive: true });

  // Burn each scene's caption into its own clip first, so caption timing
  // always matches the scene it belongs to regardless of concat order.
  const captionedClips: string[] = [];
  for (let i = 0; i < script.scenes.length; i++) {
    const scene = script.scenes[i];
    const inPath = videoClips[i];
    const outPath = path.join(captionedDir, `scene-${scene.sceneNumber}.mp4`);
    const safeCaption = scene.captionText
      .replace(/:/g, "\\:")
      .replace(/'/g, "\\'");

    await runFfmpeg([
      "-i",
      inPath,
      "-vf",
      `drawtext=text='${safeCaption}':fontcolor=white:fontsize=48:` +
        "x=(w-text_w)/2:y=h-140:box=1:boxcolor=black@0.5:boxborderw=16",
      "-c:a",
      "copy",
      outPath,
    ]);
    captionedClips.push(outPath);
  }

  await writeFile(
    videoListFile,
    captionedClips.map((f) => `file '${f}'`).join("\n")
  );
  await writeFile(
    audioListFile,
    audioClips.map((f) => `file '${f}'`).join("\n")
  );

  const combinedVideo = path.join(paths.root, "combined-video.mp4");
  const combinedAudio = path.join(paths.root, "combined-audio.m4a");

  await runFfmpeg([
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    videoListFile,
    "-c",
    "copy",
    combinedVideo,
  ]);

  await runFfmpeg([
    "-f",
    "concat",
    "-safe",
    "0",
    "-i",
    audioListFile,
    "-c:a",
    "aac",
    combinedAudio,
  ]);

  await runFfmpeg([
    "-i",
    combinedVideo,
    "-i",
    combinedAudio,
    "-c:v",
    "copy",
    "-c:a",
    "aac",
    "-map",
    "0:v:0",
    "-map",
    "1:a:0",
    "-shortest",
    paths.finalVideo,
  ]);

  console.log(`[assemble] Final video -> ${paths.finalVideo}`);
  return paths.finalVideo;
}
