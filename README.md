# Second Brain

A personal assistant app: capture notes/ideas → recall them via chat → daily planning → voice control.

This repo is being built in layers, each a working app on its own. This first
milestone covers the start of **Layer 1: Capture** — auth, the notes table,
and a capture screen that saves text notes and voice memos to Supabase.

## Tech stack

- **Frontend:** React Native (Expo), TypeScript
- **Backend:** Supabase (Postgres + Auth + Storage)
- **AI:** Anthropic API (added in later layers, for auto-tagging and chat recall)

## Project setup

### 1. Create a Supabase project

1. Create a free project at [supabase.com](https://supabase.com).
2. In the SQL editor, run the migrations in `supabase/migrations/` in order
   (`0001_notes.sql`, then `0002_storage.sql`). They create the `notes` table
   with row-level security and a private `note-attachments` storage bucket
   for voice memos.
3. Under Project Settings → API, copy the **Project URL** and **anon public
   key**.

### 2. Configure environment variables

```bash
cp .env.example .env
```

Fill in `EXPO_PUBLIC_SUPABASE_URL` and `EXPO_PUBLIC_SUPABASE_ANON_KEY` with
the values from step 1.

### 3. Install dependencies and run

```bash
npm install
npm run ios      # or: npm run android / npm run web
```

Sign up with an email/password on first launch (Supabase auth), then use the
capture screen to save a text note or record a voice memo.

## What's implemented so far

- Expo + TypeScript scaffold
- Supabase client with persisted auth session (`lib/supabase.ts`)
- Email/password sign-in and sign-up (`screens/SignInScreen.tsx`)
- `notes` table with RLS so each user only sees their own notes
  (`supabase/migrations/0001_notes.sql`)
- Private storage bucket for voice memo attachments
  (`supabase/migrations/0002_storage.sql`)
- Capture screen: text notes, voice memo recording via `expo-av`, upload to
  Supabase Storage, and a list of recent notes (`screens/CaptureScreen.tsx`)

## Data model

```
notes(
  id uuid,
  user_id uuid,
  content text,
  type text,       -- 'text' | 'voice' | 'photo'
  tags text[],
  source text,      -- 'app' for text notes, storage path for voice/photo
  created_at timestamptz
)
```

## Roadmap

- **Layer 1 (continued):** auto-tagging notes via the Claude API, photo
  capture, local keyword search
- **Layer 2 — Recall:** chat interface over your notes (keyword pre-filter +
  Claude context, no vector DB needed at this scale)
- **Layer 3 — Planning:** EventKit calendar/reminders integration, daily
  briefing, task extraction from notes
- **Layer 4 — Voice:** iOS Shortcuts + Siri integration via URL scheme
  (a true always-listening in-app assistant isn't viable for App Store
  distribution, so Shortcuts is the supported path)

## Known costs

- Apple Developer account — $99/year, required to publish to the App Store
- Anthropic API usage — pay-as-you-go, added in Layer 1's auto-tagging step
  and Layer 2's chat recall
