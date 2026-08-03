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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return jsonResponse({ error: "Missing authorization header" }, 401);

  let noteId: string | undefined;
  try {
    ({ noteId } = await req.json());
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  if (!noteId) return jsonResponse({ error: "noteId is required" }, 400);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return jsonResponse({ error: "Not authenticated" }, 401);

  const { data: note, error: fetchError } = await supabase
    .from("notes")
    .select("id, content")
    .eq("id", noteId)
    .single();
  if (fetchError || !note) return jsonResponse({ error: "Note not found" }, 404);

  if (!note.content || !note.content.trim()) {
    return jsonResponse({ tags: [], actionItems: [] });
  }

  const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });
  const message = await anthropic.messages.create({
    model: "claude-opus-5",
    max_tokens: 1024,
    thinking: { type: "disabled" },
    output_config: {
      format: {
        type: "json_schema",
        schema: {
          type: "object",
          properties: {
            tags: {
              type: "array",
              items: { type: "string" },
              description: "1-4 short lowercase topic tags, e.g. diy, biology, golf, work",
            },
            action_items: {
              type: "array",
              items: { type: "string" },
              description: "Concrete tasks or action items mentioned in the note, if any",
            },
          },
          required: ["tags", "action_items"],
          additionalProperties: false,
        },
      },
    },
    messages: [
      {
        role: "user",
        content: `Categorize this personal note and extract any action items.\n\nNote:\n${note.content}`,
      },
    ],
  });

  const textBlock = message.content.find((b) => b.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    return jsonResponse({ error: "No structured output returned" }, 502);
  }

  const parsed = JSON.parse(textBlock.text) as { tags: string[]; action_items: string[] };

  const { error: updateError } = await supabase
    .from("notes")
    .update({ tags: parsed.tags })
    .eq("id", noteId);
  if (updateError) return jsonResponse({ error: updateError.message }, 500);

  if (parsed.action_items.length > 0) {
    const { error: tasksError } = await supabase.from("tasks").insert(
      parsed.action_items.map((description) => ({
        user_id: userData.user.id,
        note_id: noteId,
        description,
      })),
    );
    if (tasksError) return jsonResponse({ error: tasksError.message }, 500);
  }

  return jsonResponse({ tags: parsed.tags, actionItems: parsed.action_items });
});
