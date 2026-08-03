import { readFile, writeFile, mkdir } from "node:fs/promises";
import path from "node:path";
import { Topic } from "../types.js";
import { topicCatalog } from "../config/topics.js";

const STATE_FILE = path.resolve(process.cwd(), "data", "queue-state.json");

interface QueueState {
  producedSlugs: string[];
}

async function readState(): Promise<QueueState> {
  try {
    return JSON.parse(await readFile(STATE_FILE, "utf-8"));
  } catch {
    return { producedSlugs: [] };
  }
}

async function writeState(state: QueueState): Promise<void> {
  await mkdir(path.dirname(STATE_FILE), { recursive: true });
  await writeFile(STATE_FILE, JSON.stringify(state, null, 2));
}

/** Returns the next topic in the catalog that hasn't been produced yet,
 * cycling back to the start once every topic has been used at least once. */
export async function nextTopic(): Promise<Topic> {
  const state = await readState();
  const unproduced = topicCatalog.filter(
    (t) => !state.producedSlugs.includes(t.slug)
  );
  return unproduced[0] ?? topicCatalog[0];
}

export function findTopic(slug: string): Topic {
  const topic = topicCatalog.find((t) => t.slug === slug);
  if (!topic) {
    throw new Error(
      `Unknown topic "${slug}". Known topics: ${topicCatalog
        .map((t) => t.slug)
        .join(", ")}`
    );
  }
  return topic;
}

export async function markProduced(slug: string): Promise<void> {
  const state = await readState();
  if (!state.producedSlugs.includes(slug)) {
    state.producedSlugs.push(slug);
    await writeState(state);
  }
}

export function listTopics(): Topic[] {
  return topicCatalog;
}
