import { Scene, Script, Topic } from "../../types.js";
import { ScriptWriter } from "./types.js";
import { estimateDurationSeconds } from "../../util/duration.js";

/**
 * Deterministic, no-API-key stand-in for the Claude scriptwriter. Turns a
 * topic's lyrics (or concept) into one scene per line/beat, so the rest of
 * the pipeline (voice, video, assembly) has real data to run against before
 * any keys are configured.
 */
export class MockScriptWriter implements ScriptWriter {
  async writeScript(topic: Topic): Promise<Script> {
    const lines = topic.lyrics ?? [topic.concept ?? topic.title];
    const scenes: Scene[] = lines.map((line, i) => ({
      sceneNumber: i + 1,
      captionText: line,
      visualPrompt: `Soft, colorful, gentle 3D animation for a baby/toddler nursery-rhyme video, no scary elements, no text on screen, illustrating: "${line}"`,
      durationSeconds: estimateDurationSeconds(line),
    }));

    return {
      topicSlug: topic.slug,
      videoTitle: `${topic.title} | Nursery Rhymes for Babies`,
      videoDescription:
        `${topic.title} — a gentle sing-along for babies and toddlers. ` +
        `[MOCK DESCRIPTION — regenerate with ANTHROPIC_API_KEY set for a real, ` +
        `SEO-considered description.]`,
      tags: topic.tags,
      scenes,
    };
  }
}
