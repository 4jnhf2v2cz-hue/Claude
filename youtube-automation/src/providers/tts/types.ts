export interface TextToSpeech {
  /** File extension (no dot) this implementation writes, e.g. "mp3" or "wav". */
  readonly fileExtension: string;
  /** Synthesizes `text` and writes an audio file to `outPath`. */
  synthesize(text: string, outPath: string): Promise<void>;
}
