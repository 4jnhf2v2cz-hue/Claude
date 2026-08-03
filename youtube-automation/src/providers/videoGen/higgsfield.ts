import { writeFile } from "node:fs/promises";
import {
  createHiggsfieldClient,
  SoulQuality,
  SoulSize,
  BatchSize,
  DoPModel,
} from "@higgsfield/client/v2";
import { VideoGenerator } from "./types.js";

/**
 * Real Higgsfield client, built on the official `@higgsfield/client` v2 SDK
 * (verified against the SDK's shipped .d.ts files, not just its README —
 * the README's own example endpoint/response shape didn't match the actual
 * types, so this follows the types).
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
  private client: ReturnType<typeof createHiggsfieldClient>;

  constructor(keyId: string, keySecret: string, private videoEndpoint: string) {
    this.client = createHiggsfieldClient({ credentials: `${keyId}:${keySecret}` });
  }

  async generateScene(
    prompt: string,
    _durationSeconds: number,
    outPath: string
  ): Promise<void> {
    const imageResponse = await this.client.subscribe("/v1/text2image/soul", {
      input: {
        prompt,
        width_and_height: SoulSize.LANDSCAPE_2048x1152, // 16:9
        quality: SoulQuality.HD,
        batch_size: BatchSize.SINGLE,
      },
      withPolling: true,
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

    const videoResponse = await this.client.subscribe(this.videoEndpoint, {
      input: {
        model: DoPModel.TURBO,
        prompt,
        input_images: [{ type: "image_url", image_url: imageUrl }],
      },
      withPolling: true,
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
}
