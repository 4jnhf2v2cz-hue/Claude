import sharp from "sharp";
import { Script } from "../types.js";
import { pathsFor } from "./paths.js";

const WIDTH = 1280;
const HEIGHT = 720;
const BACKGROUND = "#FFE9C7"; // warm, soft, non-clinical background

/**
 * Composites a simple text-on-background thumbnail with sharp — purely
 * local, no API key or cost, ever. Good enough as a placeholder/first draft;
 * swap in a real background frame (e.g. a still from the final video) by
 * passing its path once you want something less generic.
 */
export async function runThumbnailStep(script: Script): Promise<string> {
  const paths = await pathsFor(script.topicSlug);

  const lines = wrapText(script.videoTitle, 18); // ~18 chars/line at this font size
  const fontSize = 72;
  const lineHeight = fontSize * 1.15;
  const startY = HEIGHT / 2 - ((lines.length - 1) * lineHeight) / 2;

  const tspans = lines
    .map(
      (line, i) =>
        `<tspan x="50%" y="${startY + i * lineHeight}">${escapeXml(line)}</tspan>`
    )
    .join("\n");

  const svg = `
    <svg width="${WIDTH}" height="${HEIGHT}" xmlns="http://www.w3.org/2000/svg">
      <rect width="100%" height="100%" fill="${BACKGROUND}" />
      <text font-family="sans-serif" font-size="${fontSize}"
            font-weight="bold" fill="#3A2E1F" text-anchor="middle">
        ${tspans}
      </text>
    </svg>
  `;

  await sharp(Buffer.from(svg)).jpeg({ quality: 90 }).toFile(paths.thumbnail);
  console.log(`[thumbnail] -> ${paths.thumbnail}`);
  return paths.thumbnail;
}

function wrapText(text: string, maxCharsPerLine: number): string[] {
  const words = text.split(/\s+/);
  const lines: string[] = [];
  let current = "";

  for (const word of words) {
    const candidate = current ? `${current} ${word}` : word;
    if (candidate.length > maxCharsPerLine && current) {
      lines.push(current);
      current = word;
    } else {
      current = candidate;
    }
  }
  if (current) lines.push(current);

  return lines;
}

function escapeXml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
