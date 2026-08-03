import { Scene, Script, Topic } from "../../types.js";
import { ScriptWriter } from "./types.js";
import { estimateDurationSeconds } from "../../util/duration.js";

/**
 * Free, local alternative to Claude: calls a locally-running Ollama install
 * (https://ollama.com) instead of a hosted API. No key, no signup, no
 * per-token cost — the only requirement is `ollama pull <model>` done once
 * on this machine and `ollama serve` (or the Ollama app) running.
 */
export class OllamaScriptWriter implements ScriptWriter {
  constructor(private model: string, private baseUrl: string) {}

  async writeScript(topic: Topic): Promise<Script> {
    const lines = topic.lyrics ?? [topic.concept ?? topic.title];

    const prompt = `You are producing a scene breakdown for a YouTube video aimed at
babies/toddlers aged 0-3, in the "${topic.title}" nursery-rhyme/learning niche.

The video's spoken/sung content (do not change it) is, one line per scene:
${lines.map((l, i) => `${i + 1}. ${l}`).join("\n")}

Return ONLY a JSON object with this exact shape, no prose before or after:
{
  "videoTitle": "string, parent-search-optimized, under 70 characters",
  "videoDescription": "2-4 sentences, warm and parent-facing, mentions it's gentle content for babies/toddlers",
  "tags": ["8-12 lowercase search tags relevant to nursery rhymes / toddler learning"],
  "scenePrompts": ["one AI-video-generation prompt per input line, in the same order, each describing a soft, colorful, non-scary animated scene with no on-screen text"]
}

Every visual must be calm, bright, simple, and appropriate for a child under 3 — no fast cuts, no frightening imagery, no on-screen text (captions are burned in separately).`;

    const res = await fetch(`${this.baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model: this.model,
        messages: [{ role: "user", content: prompt }],
        format: "json",
        stream: false,
      }),
    });

    if (!res.ok) {
      throw new Error(
        `Ollama request failed (${res.status}): ${await res.text()}. ` +
          `Is 'ollama serve' running and has \`ollama pull ${this.model}\` been run?`
      );
    }

    const data = (await res.json()) as { message?: { content?: string } };
    const text = data.message?.content;
    if (!text) {
      throw new Error("Ollama response contained no message content");
    }

    const parsed = JSON.parse(extractJson(text)) as {
      videoTitle: string;
      videoDescription: string;
      tags: string[];
      scenePrompts: string[];
    };

    if (parsed.scenePrompts.length !== lines.length) {
      throw new Error(
        `Ollama returned ${parsed.scenePrompts.length} scene prompts for ${lines.length} lines`
      );
    }

    const scenes: Scene[] = lines.map((line, i) => ({
      sceneNumber: i + 1,
      captionText: line,
      visualPrompt: parsed.scenePrompts[i],
      durationSeconds: estimateDurationSeconds(line),
    }));

    return {
      topicSlug: topic.slug,
      videoTitle: parsed.videoTitle,
      videoDescription: parsed.videoDescription,
      tags: parsed.tags,
      scenes,
    };
  }
}

/** Strips accidental markdown code fences before JSON.parse. */
function extractJson(text: string): string {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  return (fenced ? fenced[1] : text).trim();
}
