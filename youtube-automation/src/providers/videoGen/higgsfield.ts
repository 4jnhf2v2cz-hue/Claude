import { writeFile } from "node:fs/promises";
import { VideoGenerator } from "./types.js";

interface GenerationResponse {
  id: string;
  status?: "queued" | "processing" | "completed" | "failed";
  output_url?: string;
  error?: string;
}

const POLL_INTERVAL_MS = 4000;
const MAX_POLLS = 60; // ~4 minutes per scene

/**
 * Real Higgsfield client: submits a text-to-video job, polls until
 * completion, downloads the result.
 *
 * NOTE: Higgsfield doesn't publish a single canonical public API spec —
 * access typically goes through the dashboard or an aggregator (Segmind,
 * eachlabs, VideoGenAPI, etc.), and payload shapes vary slightly between
 * them. This client targets the common `POST /v1/generations` +
 * `GET /v1/generations/{id}` polling shape. Before your first real run,
 * check the exact field names in the docs/dashboard for whichever
 * Higgsfield access you actually signed up for and adjust `submit()` below
 * if a field name differs.
 */
export class HiggsfieldVideoGenerator implements VideoGenerator {
  constructor(private apiKey: string, private baseUrl: string) {}

  async generateScene(
    prompt: string,
    durationSeconds: number,
    outPath: string
  ): Promise<void> {
    const id = await this.submit(prompt, durationSeconds);
    const outputUrl = await this.pollUntilDone(id);
    await this.download(outputUrl, outPath);
  }

  private async submit(prompt: string, durationSeconds: number): Promise<string> {
    const res = await fetch(`${this.baseUrl}/generations`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        task: "text-to-video",
        prompt,
        duration: durationSeconds,
        fps: 30,
        motion_intensity: "low", // calm, non-jarring motion for toddler content
      }),
    });

    if (!res.ok) {
      throw new Error(
        `Higgsfield submit failed (${res.status}): ${await res.text()}`
      );
    }

    const data = (await res.json()) as GenerationResponse;
    return data.id;
  }

  private async pollUntilDone(id: string): Promise<string> {
    for (let attempt = 0; attempt < MAX_POLLS; attempt++) {
      const res = await fetch(`${this.baseUrl}/generations/${id}`, {
        headers: { Authorization: `Bearer ${this.apiKey}` },
      });

      if (!res.ok) {
        throw new Error(
          `Higgsfield status check failed (${res.status}): ${await res.text()}`
        );
      }

      const data = (await res.json()) as GenerationResponse;

      if (data.status === "completed" && data.output_url) {
        return data.output_url;
      }
      if (data.status === "failed") {
        throw new Error(`Higgsfield generation ${id} failed: ${data.error}`);
      }

      await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
    }

    throw new Error(`Higgsfield generation ${id} timed out waiting to complete`);
  }

  private async download(url: string, outPath: string): Promise<void> {
    const res = await fetch(url);
    if (!res.ok) {
      throw new Error(`Failed to download generated clip: ${res.status}`);
    }
    await writeFile(outPath, Buffer.from(await res.arrayBuffer()));
  }
}
