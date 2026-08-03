import { spawn } from "node:child_process";

/** Runs the system `ffmpeg` binary. Free/open-source — install with your
 * package manager (e.g. `apt install ffmpeg` / `brew install ffmpeg`); it's
 * the only non-JS dependency this pipeline needs. */
export function runFfmpeg(args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const proc = spawn("ffmpeg", ["-y", ...args], { stdio: "pipe" });
    let stderr = "";
    proc.stderr.on("data", (chunk) => (stderr += chunk.toString()));

    proc.on("error", (err) => {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        reject(
          new Error(
            "ffmpeg not found on PATH. Install it (e.g. `apt install ffmpeg` " +
              "or `brew install ffmpeg`) — it's free and required for local " +
              "mock video generation and final assembly."
          )
        );
      } else {
        reject(err);
      }
    });

    proc.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`ffmpeg exited with code ${code}:\n${stderr}`));
    });
  });
}
