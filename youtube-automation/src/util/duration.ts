/** Slow, toddler-paced estimate (~2 words/sec) so mock audio/video durations
 * for a line line up with each other without needing to probe real audio. */
export function estimateDurationSeconds(text: string): number {
  const words = text.trim().split(/\s+/).filter(Boolean).length;
  return Math.max(3, Math.ceil(words / 2));
}
