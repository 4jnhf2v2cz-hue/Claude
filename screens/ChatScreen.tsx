import { useState } from 'react';
import {
  ActivityIndicator,
  FlatList,
  KeyboardAvoidingView,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { supabase } from '../lib/supabase';

interface ChatMessage {
  id: string;
  role: 'user' | 'assistant';
  text: string;
}

const STOPWORDS = new Set([
  'the', 'a', 'an', 'what', 'when', 'where', 'who', 'how', 'why', 'did', 'do', 'does',
  'is', 'are', 'was', 'were', 'i', 'my', 'me', 'about', 'on', 'in', 'to', 'of', 'for',
]);

function extractKeywords(question: string): string[] {
  return Array.from(
    new Set(
      question
        .toLowerCase()
        .replace(/[^a-z0-9\s]/g, '')
        .split(/\s+/)
        .filter((word) => word.length > 2 && !STOPWORDS.has(word)),
    ),
  );
}

export default function ChatScreen() {
  const [question, setQuestion] = useState('');
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [asking, setAsking] = useState(false);

  const ask = async () => {
    const trimmed = question.trim();
    if (!trimmed || asking) return;

    const userMessage: ChatMessage = { id: `${Date.now()}-u`, role: 'user', text: trimmed };
    setMessages((prev) => [...prev, userMessage]);
    setQuestion('');
    setAsking(true);

    try {
      const keywords = extractKeywords(trimmed);
      let notes: { content: string; tags: string[]; type: string; created_at: string }[] = [];

      if (keywords.length > 0) {
        const orFilter = keywords
          .map((kw) => `content.ilike.%${kw}%,tags.cs.{${kw}}`)
          .join(',');
        const { data } = await supabase
          .from('notes')
          .select('content, tags, type, created_at')
          .or(orFilter)
          .order('created_at', { ascending: false })
          .limit(20);
        notes = data ?? [];
      }

      if (notes.length === 0) {
        const { data } = await supabase
          .from('notes')
          .select('content, tags, type, created_at')
          .order('created_at', { ascending: false })
          .limit(20);
        notes = data ?? [];
      }

      const { data, error } = await supabase.functions.invoke('chat', {
        body: { question: trimmed, notes },
      });
      if (error) throw error;

      const answer: string = data?.answer || "I couldn't find an answer in your notes.";
      setMessages((prev) => [...prev, { id: `${Date.now()}-a`, role: 'assistant', text: answer }]);
    } catch (err) {
      setMessages((prev) => [
        ...prev,
        { id: `${Date.now()}-e`, role: 'assistant', text: `Error: ${(err as Error).message}` },
      ]);
    } finally {
      setAsking(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      keyboardVerticalOffset={90}
    >
      <Text style={styles.heading}>Recall</Text>

      <FlatList
        style={styles.list}
        data={messages}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <View style={[styles.bubble, item.role === 'user' ? styles.userBubble : styles.assistantBubble]}>
            <Text style={item.role === 'user' ? styles.userText : styles.assistantText}>{item.text}</Text>
          </View>
        )}
        ListEmptyComponent={
          <Text style={styles.emptyText}>Ask "What did I decide about X?" to recall your notes.</Text>
        }
      />

      {asking && <ActivityIndicator style={styles.indicator} />}

      <View style={styles.inputRow}>
        <TextInput
          style={styles.input}
          placeholder="Ask about your notes..."
          value={question}
          onChangeText={setQuestion}
          onSubmitEditing={ask}
          returnKeyType="send"
        />
        <Pressable style={[styles.sendButton, asking && styles.sendButtonDisabled]} onPress={ask} disabled={asking}>
          <Text style={styles.sendText}>Ask</Text>
        </Pressable>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#fff',
    paddingHorizontal: 20,
    paddingTop: 60,
  },
  heading: {
    fontSize: 28,
    fontWeight: '700',
    marginBottom: 16,
  },
  list: {
    flex: 1,
  },
  bubble: {
    borderRadius: 12,
    padding: 12,
    marginBottom: 10,
    maxWidth: '85%',
  },
  userBubble: {
    backgroundColor: '#111',
    alignSelf: 'flex-end',
  },
  assistantBubble: {
    backgroundColor: '#f0f0f0',
    alignSelf: 'flex-start',
  },
  userText: {
    color: '#fff',
    fontSize: 15,
  },
  assistantText: {
    color: '#111',
    fontSize: 15,
  },
  indicator: {
    marginBottom: 8,
  },
  inputRow: {
    flexDirection: 'row',
    gap: 10,
    paddingBottom: 16,
    paddingTop: 8,
  },
  input: {
    flex: 1,
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
  },
  sendButton: {
    backgroundColor: '#111',
    borderRadius: 10,
    paddingHorizontal: 20,
    justifyContent: 'center',
  },
  sendButtonDisabled: {
    opacity: 0.4,
  },
  sendText: {
    color: '#fff',
    fontWeight: '600',
  },
  emptyText: {
    color: '#999',
    marginTop: 40,
    textAlign: 'center',
  },
});
