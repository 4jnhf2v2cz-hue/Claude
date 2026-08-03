import { createClient } from "npm:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk@0.32.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface NoteContext {
  content: string;
  tags: string[];
  type: string;
  created_at: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Missing authorization header" }, 401);

  let question: string | undefined;
  let notes: NoteContext[] | undefined;
  try {
    ({ question, notes } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  if (!question || !question.trim()) return jsonResponse({ error: "question is required" }, 400);
  if (!Array.isArray(notes)) return jsonResponse({ error: "notes must be an array" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return jsonResponse({ error: "Not authenticated" }, 401);

  const context = notes.length
    ? notes
        .map(
          (n, i) =>
            `[Note ${i + 1} — ${new Date(n.created_at).toLocaleDateString()} — tags: ${n.tags.join(", ") || "none"}]\n${n.content}`,
        )
        .join("\n\n")
    : "(no matching notes found)";

  const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
  const message = await anthropic.messages.create({
    model: "claude-opus-5",
    max_tokens: 2048,
    system:
      "You are the recall assistant for a personal notes app called Second Brain. Answer the user's question using only the notes provided as context. If the notes don't contain the answer, say so plainly rather than guessing. Be concise and reference specific notes when relevant.",
    messages: [
      {
        role: "user",
        content: `Notes:\n${context}\n\nQuestion: ${question}`,
      },
    ],
  });

  const textBlock = message.content.find((b) => b.type === "text");
  const answer = textBlock && textBlock.type === "text" ? textBlock.text : "";

  return jsonResponse({ answer });
});
