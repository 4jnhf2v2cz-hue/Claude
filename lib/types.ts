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

export interface Task {
  id: string;
  user_id: string;
  note_id: string | null;
  description: string;
  completed: boolean;
  due_date: string | null;
  created_at: string;
}
