import { supabase } from './supabase';

export async function quickCaptureText(userId: string, content: string) {
  const trimmed = content.trim();
  if (!trimmed) return;

  const { data, error } = await supabase
    .from('notes')
    .insert({ user_id: userId, content: trimmed, type: 'text', tags: [], source: 'shortcut' })
    .select('id')
    .single();
  if (error) throw error;

  if (data) {
    supabase.functions.invoke('process-note', { body: { noteId: data.id } }).catch(() => {
      // Auto-tagging is best-effort; the note is already saved.
    });
  }
}
