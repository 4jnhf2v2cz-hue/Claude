import { readFile, writeFile } from "node:fs/promises";
import { Script, Topic } from "../types.js";
import { ScriptWriter } from "../providers/llm/types.js";
import { ClaudeScriptWriter } from "../providers/llm/claude.js";
import { MockScriptWriter } from "../providers/llm/mock.js";
import { pathsFor } from "./paths.js";

export function getScriptWriter(forceMock: boolean): ScriptWriter {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!forceMock && apiKey) {
    return new ClaudeScriptWriter(apiKey);
  }
  console.log("[script] No ANTHROPIC_API_KEY (or --dry-run) — using mock scriptwriter");
  return new MockScriptWriter();
}

export async function runScriptStep(
  topic: Topic,
  forceMock: boolean
): Promise<Script> {
  const writer = getScriptWriter(forceMock);
  const script = await writer.writeScript(topic);
  const paths = await pathsFor(topic.slug);
  await writeFile(paths.scriptFile, JSON.stringify(script, null, 2));
  console.log(`[script] Wrote ${paths.scriptFile}`);
  return script;
}

export async function loadScript(topicSlug: string): Promise<Script> {
  const paths = await pathsFor(topicSlug);
  return JSON.parse(await readFile(paths.scriptFile, "utf-8"));
}
