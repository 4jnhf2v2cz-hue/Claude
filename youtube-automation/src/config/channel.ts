export const channel = {
  name: "Placeholder — rename before launch",
  description:
    "Gentle nursery rhymes and simple learning videos for babies and toddlers (0-3).",
  /**
   * Content squarely aimed at children under 3 must be declared "Made for
   * Kids" to YouTube. This disables personalized ads, comments, live chat,
   * notifications, and some end-screen features — see README.md "Compliance"
   * section before ever setting this to false.
   */
  madeForKids: (process.env.CHANNEL_MADE_FOR_KIDS ?? "true") !== "false",
  /**
   * Never auto-publish publicly. Every upload lands as "private" (or
   * "unlisted") so a human reviews it in YouTube Studio before it goes live —
   * this matters generally, and doubly so for kids' content.
   */
  defaultPrivacyStatus: process.env.DEFAULT_PRIVACY_STATUS ?? "private",
} as const;
