import Anthropic from "@anthropic-ai/sdk";
import { Scene, Script, Topic } from "../../types.js";
import { ScriptWriter } from "./types.js";
import { estimateDurationSeconds } from "../../util/duration.js";

const MODEL = "claude-sonnet-5";

/**
 * Real scriptwriter backed by the Claude API. It NEVER asks the model to
 * write or alter lyrics for a classic rhyme — those are public-domain text
 * from src/config/topics.ts, used verbatim. The model only produces: a scene
 * breakdown (one visual prompt per line/beat), and search-optimized
 * title/description/tags. This avoids the model confidently inventing wrong
 * lyrics to a song real viewers already know by heart.
 */
export class ClaudeScriptWriter implements ScriptWriter {
  private client: Anthropic;

  constructor(apiKey: string) {
    this.client = new Anthropic({ apiKey });
  }

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

    const response = await this.client.messages.create({
      model: MODEL,
      max_tokens: 2048,
      messages: [{ role: "user", content: prompt }],
    });

    const textBlock = response.content.find((block) => block.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new Error("Claude response contained no text block");
    }

    const parsed = JSON.parse(extractJson(textBlock.text)) as {
      videoTitle: string;
      videoDescription: string;
      tags: string[];
      scenePrompts: string[];
    };

    if (parsed.scenePrompts.length !== lines.length) {
      throw new Error(
        `Claude returned ${parsed.scenePrompts.length} scene prompts for ${lines.length} lines`
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
