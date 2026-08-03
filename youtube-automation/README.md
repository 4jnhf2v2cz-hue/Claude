# YouTube Automation — Nursery Rhymes & Toddler Learning (0-3)

A local CLI pipeline that takes a nursery-rhyme/toddler-learning topic and
produces a finished, captioned video ready for review and upload:

```
research -> script -> voice -> video -> assemble -> thumbnail -> upload
```

Every step runs today with **zero API keys**, using mock providers (a silent
placeholder audio track, a solid-color placeholder video clip with the scene
prompt burned in). Add real credentials to `.env` and each step
transparently switches to the real provider — no code changes needed.

See `../YOUTUBE_AUTOMATION_BUSINESS_PLAN.md` at the repo root for the
business model this pipeline implements; this README is the operator's guide
to actually running it.

## Prerequisites

- Node.js 18+
- `ffmpeg` on your PATH — free/open-source, install with `apt install ffmpeg`
  (Linux) or `brew install ffmpeg` (macOS). This is the only non-JS
  dependency and the only thing that isn't a plain `npm install`.

## Scripting: Claude vs. free local Ollama

The script step (`src/pipeline/script.ts`) picks a provider in this order:
`ANTHROPIC_API_KEY` set → Claude; else `OLLAMA_MODEL` set → your local
Ollama install (**genuinely $0, no signup, no key**); else → mock.

To use the free path:

```bash
# once: install Ollama (ollama.com), then pull a model
ollama pull llama3.1
ollama serve   # or just leave the Ollama desktop app running
```

```bash
# in .env
OLLAMA_MODEL=llama3.1
```

Quality is lower than Claude for nuanced writing, but for this pipeline's
templated task (turn a fixed line into one calm visual prompt) a mid-size
open model is plenty — and it costs nothing regardless of volume, since
nothing leaves your machine.

## Setup

```bash
npm install
cp .env.example .env
```

Leave `.env` empty and everything runs in mock mode. Fill in keys as you get
each account — see the header comments in `.env.example` for what each
step needs.

## Running it

```bash
npm run build

# Full pipeline for the next un-produced topic in the catalog
node dist/src/orchestrator.js run

# Or a specific topic
node dist/src/orchestrator.js run --topic wheels-on-the-bus

# Force mock providers even if you've set real API keys (useful for testing
# changes without burning API credits/quota)
node dist/src/orchestrator.js run --dry-run --topic old-macdonald

# Individual steps (each needs the previous step's output on disk already)
node dist/src/orchestrator.js script --topic twinkle-twinkle
node dist/src/orchestrator.js voice --topic twinkle-twinkle
node dist/src/orchestrator.js video --topic twinkle-twinkle
node dist/src/orchestrator.js assemble --topic twinkle-twinkle
node dist/src/orchestrator.js thumbnail --topic twinkle-twinkle

# List the topic catalog
node dist/src/orchestrator.js topics
```

Output for each topic lands in `output/<topic-slug>/`: `script.json`,
`audio/`, `scenes/`, `final.mp4`, `thumbnail.jpg`.

**Upload is deliberately a separate, explicit step** — it's the one part of
this pipeline that touches your real YouTube channel, so it's never run
implicitly by `run` and requires `--confirm`:

```bash
node dist/src/orchestrator.js upload --topic twinkle-twinkle --confirm
```

It always uploads as `private` (configurable via `DEFAULT_PRIVACY_STATUS` in
`.env`, but think hard before changing it) so a human reviews the video in
YouTube Studio before it ever goes public.

### One-time YouTube OAuth setup

Upload needs a refresh token, obtained once:

1. In Google Cloud Console, create a project, enable the **YouTube Data API
   v3**, and create an OAuth client of type **Desktop app**. Free — no
   billing required at this quota tier.
2. `YOUTUBE_CLIENT_ID=... YOUTUBE_CLIENT_SECRET=... npm run youtube-auth`
3. Follow the printed URL, sign in as the channel owner, paste the code back
   in. It prints a `YOUTUBE_REFRESH_TOKEN` — add it to `.env`.

## Compliance — read this before your first real upload

Content squarely aimed at children under 3, like this catalog, is legally
**"Made for Kids"** content under the FTC's COPPA rule, and YouTube requires
it be declared as such (`src/config/channel.ts` sets
`selfDeclaredMadeForKids: true` by default — do not flip this to `false`
without understanding the consequences below). That declaration:

- **Disables personalized ads** — only contextual ads run, at a materially
  lower CPM than the general blended revenue math in the top-level business
  plan. Top kids channels still earn well because young children rewatch
  the same video far more than any other audience, driving huge view counts
  that partially offset the lower per-view rate — but budget for lower CPM,
  not the finance/tech-niche numbers.
- **Disables comments, live chat, and the notifications bell** on affected
  videos.
- Prohibits collecting personal data from viewers for ad targeting.

Also worth knowing before scaling this up:

- **Lyrics are never LLM-generated.** `src/config/topics.ts` hard-codes the
  traditional public-domain text for each classic rhyme, and the scriptwriter
  (mock or Claude) is only ever asked for a scene breakdown and
  title/description/tags — never to "write" or "improve" the song itself.
  This avoids a model confidently inventing wrong lyrics to a song viewers
  already know by heart.
- **YouTube's synthetic-media disclosure**: separately from the kids
  declaration, YouTube requires disclosing AI-generated/altered content that
  looks realistic. This pipeline's visuals (Higgsfield-generated) likely
  qualify — check the current disclosure checkbox in YouTube Studio's
  upload flow for your content style before publishing.
- **Music licensing**: use the YouTube Audio Library or content you have
  rights to for any background music you add — this pipeline doesn't add
  music by default.

## How the mock providers work (so you can trust dry-run mode)

- **Script** (`src/providers/llm/mock.ts`): one scene per lyric line, a
  generic placeholder description, real tags from the topic config.
- **Voice** (`src/providers/tts/mock.ts`): a genuinely valid silent WAV file,
  duration estimated from word count (`src/util/duration.ts`) at a slow,
  toddler-appropriate pace — the same estimate used to size the placeholder
  video clip, so mock audio and video durations line up.
- **Video** (`src/providers/videoGen/mock.ts`): a solid-color `ffmpeg`
  `lavfi` clip with the scene's visual prompt burned in as text — no network
  call at all.
- **Thumbnail** (`src/pipeline/thumbnail.ts`): always real — it's rendered
  locally with `sharp`, no API involved regardless of mode.

## Note on the Higgsfield client

`src/providers/videoGen/higgsfield.ts` targets the common
`POST /v1/generations` + poll `GET /v1/generations/{id}` shape used by
Higgsfield's dashboard/aggregator access. Higgsfield doesn't publish one
single canonical public spec — exact field names can vary depending on which
access path you're on (direct dashboard key vs. an aggregator like Segmind,
eachlabs, or VideoGenAPI). Before your first real (non-mock) video run, check
the field names in whichever docs/dashboard you actually signed up with and
adjust the `submit()` method if something doesn't match.
