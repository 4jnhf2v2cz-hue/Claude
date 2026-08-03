export type NoteType = 'text' | 'voice' | 'photo';

export interface Note {
  id: string;
  user_id: string;
  content: string;
  type: NoteType;
  tags: string[];
  source: string | null;
  created_at: string;
}
