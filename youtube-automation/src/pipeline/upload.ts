import { createReadStream } from "node:fs";
import { google } from "googleapis";
import { Script } from "../types.js";
import { pathsFor } from "./paths.js";
import { channel } from "../config/channel.js";

export interface UploadResult {
  videoId: string;
  studioUrl: string;
}

function getAuthedYoutubeClient() {
  const clientId = process.env.YOUTUBE_CLIENT_ID;
  const clientSecret = process.env.YOUTUBE_CLIENT_SECRET;
  const refreshToken = process.env.YOUTUBE_REFRESH_TOKEN;

  if (!clientId || !clientSecret || !refreshToken) {
    throw new Error(
      "Missing YOUTUBE_CLIENT_ID / YOUTUBE_CLIENT_SECRET / YOUTUBE_REFRESH_TOKEN. " +
        "Run `npm run youtube-auth` once to obtain a refresh token (see scripts/youtube-oauth-setup.ts), " +
        "then add all three to .env. Upload cannot run in mock mode — there is no safe " +
        "placeholder for publishing to a real channel."
    );
  }

  const oauth2Client = new google.auth.OAuth2(clientId, clientSecret);
  oauth2Client.setCredentials({ refresh_token: refreshToken });
  return google.youtube({ version: "v3", auth: oauth2Client });
}

/**
 * Uploads the assembled video. Always uploads as `channel.defaultPrivacyStatus`
 * (private by default) and always sets `selfDeclaredMadeForKids` from
 * config — see README.md "Compliance" section before changing either.
 */
export async function runUploadStep(script: Script): Promise<UploadResult> {
  const paths = await pathsFor(script.topicSlug);
  const youtube = getAuthedYoutubeClient();

  const res = await youtube.videos.insert({
    part: ["snippet", "status"],
    requestBody: {
      snippet: {
        title: script.videoTitle,
        description: script.videoDescription,
        tags: script.tags,
      },
      status: {
        privacyStatus: channel.defaultPrivacyStatus as "private" | "unlisted" | "public",
        selfDeclaredMadeForKids: channel.madeForKids,
      },
    },
    media: {
      body: createReadStream(paths.finalVideo),
    },
  });

  const videoId = res.data.id;
  if (!videoId) {
    throw new Error("YouTube upload succeeded but returned no video id");
  }

  await youtube.thumbnails.set({
    videoId,
    media: { body: createReadStream(paths.thumbnail) },
  });

  const studioUrl = `https://studio.youtube.com/video/${videoId}/edit`;
  console.log(`[upload] Uploaded as ${channel.defaultPrivacyStatus} -> ${studioUrl}`);
  console.log("[upload] Review it in Studio before publishing.");

  return { videoId, studioUrl };
}
