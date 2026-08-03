import { readFile, writeFile } from "node:fs/promises";
import { Script, Topic } from "../types.js";
import { ScriptWriter } from "../providers/llm/types.js";
import { ClaudeScriptWriter } from "../providers/llm/claude.js";
import { OllamaScriptWriter } from "../providers/llm/ollama.js";
import { MockScriptWriter } from "../providers/llm/mock.js";
import { pathsFor } from "./paths.js";

/**
 * Precedence: Claude (if you've set a key and want the quality) > local
 * Ollama (free, set OLLAMA_MODEL to opt in) > mock. Ollama never costs
 * anything and needs no signup, so it's the default "free tier" path once
 * OLLAMA_MODEL is set — see .env.example.
 */
export function getScriptWriter(forceMock: boolean): ScriptWriter {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!forceMock && apiKey) {
    return new ClaudeScriptWriter(apiKey);
  }

  const ollamaModel = process.env.OLLAMA_MODEL;
  if (!forceMock && ollamaModel) {
    const baseUrl = process.env.OLLAMA_BASE_URL ?? "http://localhost:11434";
    console.log(`[script] Using local Ollama (${ollamaModel} @ ${baseUrl}) — free, no API key`);
    return new OllamaScriptWriter(ollamaModel, baseUrl);
  }

  console.log(
    "[script] No ANTHROPIC_API_KEY or OLLAMA_MODEL (or --dry-run) — using mock scriptwriter"
  );
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
