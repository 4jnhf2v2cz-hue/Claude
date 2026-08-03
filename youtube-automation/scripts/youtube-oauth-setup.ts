/**
 * One-time helper to mint a YOUTUBE_REFRESH_TOKEN. Run with:
 *   YOUTUBE_CLIENT_ID=... YOUTUBE_CLIENT_SECRET=... npm run youtube-auth
 *
 * Prerequisite: create an OAuth client (type "Desktop app") in Google Cloud
 * Console for a project with the YouTube Data API v3 enabled, and use its
 * client ID/secret here. This is free (no Google Cloud billing required for
 * this quota tier).
 */
import { createInterface } from "node:readline/promises";
import { google } from "googleapis";

const clientId = process.env.YOUTUBE_CLIENT_ID;
const clientSecret = process.env.YOUTUBE_CLIENT_SECRET;

if (!clientId || !clientSecret) {
  console.error("Set YOUTUBE_CLIENT_ID and YOUTUBE_CLIENT_SECRET first.");
  process.exit(1);
}

const REDIRECT_URI = "urn:ietf:wg:oauth:2.0:oob";
const oauth2Client = new google.auth.OAuth2(clientId, clientSecret, REDIRECT_URI);

const authUrl = oauth2Client.generateAuthUrl({
  access_type: "offline",
  prompt: "consent",
  scope: ["https://www.googleapis.com/auth/youtube.upload"],
});

console.log("1. Open this URL, sign in as the channel's owner, and approve access:\n");
console.log(authUrl);
console.log("\n2. Paste the code Google shows you below.\n");

const rl = createInterface({ input: process.stdin, output: process.stdout });
const code = await rl.question("Code: ");
rl.close();

const { tokens } = await oauth2Client.getToken(code.trim());

console.log("\nAdd this to your .env:\n");
console.log(`YOUTUBE_REFRESH_TOKEN=${tokens.refresh_token}`);
