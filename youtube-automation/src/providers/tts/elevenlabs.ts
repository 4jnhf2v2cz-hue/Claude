import { writeFile } from "node:fs/promises";
import { TextToSpeech } from "./types.js";

const BASE_URL = "https://api.elevenlabs.io/v1";

export class ElevenLabsTts implements TextToSpeech {
  readonly fileExtension = "mp3";

  constructor(private apiKey: string, private voiceId: string) {}

  async synthesize(text: string, outPath: string): Promise<void> {
    const res = await fetch(`${BASE_URL}/text-to-speech/${this.voiceId}`, {
      method: "POST",
      headers: {
        "xi-api-key": this.apiKey,
        "Content-Type": "application/json",
        Accept: "audio/mpeg",
      },
      body: JSON.stringify({
        text,
        model_id: "eleven_multilingual_v2",
        voice_settings: { stability: 0.6, similarity_boost: 0.8 },
      }),
    });

    if (!res.ok) {
      throw new Error(
        `ElevenLabs TTS failed (${res.status}): ${await res.text()}`
      );
    }

    const audio = Buffer.from(await res.arrayBuffer());
    await writeFile(outPath, audio);
  }
}
