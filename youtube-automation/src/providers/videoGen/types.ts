export interface VideoGenerator {
  /** Generates a single scene clip and writes it to `outPath` (mp4). */
  generateScene(
    prompt: string,
    durationSeconds: number,
    outPath: string
  ): Promise<void>;
}
