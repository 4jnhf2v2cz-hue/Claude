import { writeFile } from "node:fs/promises";
import { VideoGenerator } from "./types.js";

const BASE_URL = "https://platform.higgsfield.ai";
const POLL_INTERVAL_MS = 3000;
const MAX_POLL_MS = 5 * 60 * 1000;

interface V2Response {
  status: "queued" | "in_progress" | "completed" | "failed" | "nsfw";
  request_id: string;
  images?: { url: string }[];
  video?: { url: string };
}

/**
 * Real Higgsfield client, calling the live API directly rather than through
 * `@higgsfield/client`'s v2 `subscribe()` wrapper: that wrapper sends the
 * input fields flat in the POST body, but the live API rejects that with
 * `422 body.params: Field required` — the input must be wrapped under a
 * `params` key. Auth header, base URL, and the polling endpoint below are
 * taken from the SDK's own source (dist/v2/client.js), which gets those
 * parts right; only its request-body shape is wrong.
 *
 * Higgsfield's catalog is image-to-video, not pure text-to-video: there is
 * no "type a prompt, get a video" endpoint. So each scene is generated in
 * two steps:
 *   1. "/v1/text2image/soul" turns the scene's visual prompt into a still
 *      frame
 *   2. an image-to-video endpoint ("/v1/image2video/dop" by default,
 *      configurable via HIGGSFIELD_ENDPOINT) animates that still into a
 *      short clip
 *
 * Check cloud.higgsfield.ai's own Applications/Playground page for the
 * exact endpoint names available on your account before relying on the
 * defaults below — Higgsfield's catalog can vary by plan.
 */
export class HiggsfieldVideoGenerator implements VideoGenerator {
  private authHeader: string;

  constructor(keyId: string, keySecret: string, private videoEndpoint: string) {
    this.authHeader = `Key ${keyId}:${keySecret}`;
  }

  async generateScene(
    prompt: string,
    _durationSeconds: number,
    outPath: string
  ): Promise<void> {
    const imageResponse = await this.submitAndPoll("/v1/text2image/soul", {
      prompt,
      width_and_height: "1696x960", // 16:9, smaller/cheaper than 2048x1152
      quality: "720p",
      batch_size: 1,
    });

    if (imageResponse.status !== "completed") {
      throw new Error(
        `Higgsfield text-to-image did not complete for prompt "${prompt}" (status: ${imageResponse.status})`
      );
    }
    const imageUrl = imageResponse.images?.[0]?.url;
    if (!imageUrl) {
      throw new Error("Higgsfield text-to-image completed but returned no image URL");
    }

    const videoResponse = await this.submitAndPoll(this.videoEndpoint, {
      model: "dop-turbo",
      prompt,
      input_images: [{ type: "image_url", image_url: imageUrl }],
    });

    if (videoResponse.status !== "completed") {
      throw new Error(
        `Higgsfield image-to-video did not complete for prompt "${prompt}" (status: ${videoResponse.status})`
      );
    }
    const videoUrl = videoResponse.video?.url;
    if (!videoUrl) {
      throw new Error("Higgsfield image-to-video completed but returned no video URL");
    }

    const res = await fetch(videoUrl);
    if (!res.ok) {
      throw new Error(`Failed to download generated clip: ${res.status}`);
    }
    await writeFile(outPath, Buffer.from(await res.arrayBuffer()));
  }

  private async submitAndPoll(
    endpoint: string,
    params: Record<string, unknown>
  ): Promise<V2Response> {
    const submitRes = await fetch(`${BASE_URL}${endpoint}`, {
      method: "POST",
      headers: {
        Authorization: this.authHeader,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ params }),
    });

    if (!submitRes.ok) {
      throw new Error(
        `Higgsfield ${endpoint} submit failed (${submitRes.status}): ${await submitRes.text()}`
      );
    }

    let response = (await submitRes.json()) as V2Response;
    const startTime = Date.now();

    while (
      response.status !== "completed" &&
      response.status !== "failed" &&
      response.status !== "nsfw"
    ) {
      if (Date.now() - startTime > MAX_POLL_MS) {
        throw new Error(`Higgsfield ${endpoint} timed out waiting to complete`);
      }
      await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));

      const pollRes = await fetch(`${BASE_URL}/requests/${response.request_id}/status`, {
        headers: { Authorization: this.authHeader },
      });
      if (!pollRes.ok) {
        throw new Error(
          `Higgsfield status check failed (${pollRes.status}): ${await pollRes.text()}`
        );
      }
      response = (await pollRes.json()) as V2Response;
    }

    return response;
  }
}
