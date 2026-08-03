# Second Brain

A personal assistant app: capture notes/ideas → recall them via chat → daily
planning → voice control.

All four layers from the build spec are implemented: capture (text, voice,
photo, auto-tagging), recall (chat over your notes), planning (calendar,
reminders, daily briefing, task extraction), and voice capture via iOS
Shortcuts.

## Tech stack

- **Frontend:** React Native (Expo), TypeScript
- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions)
- **AI:** Anthropic API (Claude), called from Supabase Edge Functions so the
  API key never ships inside the app bundle

## Project setup

### 1. Create a Supabase project

1. Create a free project at [supabase.com](https://supabase.com).
2. In the SQL editor, run the migrations in `supabase/migrations/` in order:
   - `0001_notes.sql` — the `notes` table with row-level security
   - `0002_storage.sql` — a private `note-attachments` storage bucket for
     voice memos and photos
   - `0003_tasks.sql` — the `tasks` table (action items extracted from notes)
3. Under Project Settings → API, copy the **Project URL** and **anon public
   key**.

### 2. Configure environment variables

```bash
cp .env.example .env
```

Fill in `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` with
the values from step 1.

### 3. Deploy the Edge Functions

Auto-tagging and chat recall call Claude from two Supabase Edge Functions
(`supabase/functions/process-note`, `supabase/functions/chat`) so the
Anthropic API key stays server-side — a mobile app bundle is not a safe place
to embed a secret key, since it can be extracted from the compiled app.

```bash
npx supabase login
npx supabase link --project-ref <your-project-ref>
npx supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
npx supabase functions deploy process-note
npx supabase functions deploy chat
```

### 4. Install dependencies and run

```bash
npm install
npm run ios      # or: npm run android / npm run web
```

Sign up with an email/password on first launch (Supabase auth), then use the
capture screen to save a text note, record a voice memo, or take a photo.

## What's implemented

### Layer 1 — Capture

- Text notes, voice memo recording (`expo-av`), and photo capture
  (`expo-image-picker`), all uploaded to Supabase (`screens/CaptureScreen.tsx`)
- Auto-tagging on save via the `process-note` Edge Function, which calls
  Claude and writes tags back onto the note
- Local keyword/tag search (`screens/SearchScreen.tsx`)

### Layer 2 — Recall

- Chat screen (`screens/ChatScreen.tsx`) that keyword-pre-filters your notes
  client-side, then sends the question + matched notes to the `chat` Edge
  Function for a Claude-generated answer grounded in your notes

### Layer 3 — Planning

- `screens/PlanningScreen.tsx` pulls today's Calendar events and Reminders via
  `expo-calendar` (EventKit), your open action items (extracted from notes by
  `process-note` into the `tasks` table), and your most recent notes into one
  daily briefing

### Layer 4 — Voice

- iOS Shortcuts integration via a custom URL scheme: a Shortcut that opens
  `secondbrain://capture?text=<your text>` (or dictates text into that
  parameter) creates a note without opening the app UI — no App Store voice
  restrictions, since there's no background always-listening assistant

  **To set up the Shortcut:** in the Shortcuts app, create a new shortcut,
  add a "Dictate Text" (or "Ask for Input") action, then add an "Open URLs"
  action with:
  `secondbrain://capture?text=[Dictated Text, URL-encoded]`.
  Add it to Siri with a phrase like "add a note".

## Data model

```
notes(
  id uuid, user_id uuid, content text,
  type text,        -- 'text' | 'voice' | 'photo'
  tags text[], source text, created_at timestamptz
)

tasks(
  id uuid, user_id uuid, note_id uuid,
  description text, completed boolean, due_date date, created_at timestamptz
)
```

## Known costs

- Apple Developer account — $99/year, required to publish to the App Store
- Anthropic API usage — pay-as-you-go, used by auto-tagging and chat recall;
  low volume for personal use is a few pounds a month

## Not yet done

- **Device testing.** This was built and typechecked in a container with no
  iOS/Android runtime — run `npm run ios` (or open in Expo Go) and walk
  through capture, search, recall, and planning on a real device or
  simulator before relying on it.
- **App Store submission.** Requires your own Apple Developer account,
  screenshots, and App Store Connect metadata — a TestFlight/App Store
  submission is a real-world action with real costs and consequences, so
  it's left for you to drive once the app has been tested on-device.
