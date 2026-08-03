import { VideoGenerator } from "./types.js";
import { runFfmpeg } from "../../util/ffmpeg.js";

const PALETTE = ["0xFFE5B4", "0xB4E5FF", "0xC8FFB4", "0xFFC8F0", "0xFFF3B0"];

/**
 * No-API-key stand-in: renders a solid-color placeholder clip with the scene
 * prompt burned in as text, using ffmpeg's built-in lavfi source (no external
 * calls, no cost). Swap in HiggsfieldVideoGenerator once HIGGSFIELD_API_KEY
 * is set for real AI-generated visuals.
 */
export class MockVideoGenerator implements VideoGenerator {
  async generateScene(
    prompt: string,
    durationSeconds: number,
    outPath: string
  ): Promise<void> {
    const color = PALETTE[Math.floor(Math.random() * PALETTE.length)];
    const safeText = prompt
      .replace(/:/g, "\\:")
      .replace(/'/g, "\\'")
      .slice(0, 200);

    await runFfmpeg([
      "-f",
      "lavfi",
      "-i",
      `color=c=${color}:s=1920x1080:d=${durationSeconds}`,
      "-vf",
      `drawtext=text='${safeText}':fontcolor=black:fontsize=36:x=(w-text_w)/2:y=(h-text_h)/2:box=1:boxcolor=white@0.6:boxborderw=20`,
      "-r",
      "30",
      "-pix_fmt",
      "yuv420p",
      outPath,
    ]);
  }
}
