import { useState } from 'react';
import { ActivityIndicator, FlatList, StyleSheet, Text, TextInput, View } from 'react-native';
import { supabase } from '../lib/supabase';
import type { Note } from '../lib/types';

export default function SearchScreen() {
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Note[]>([]);
  const [loading, setLoading] = useState(false);
  const [searched, setSearched] = useState(false);

  const runSearch = async (value: string) => {
    setQuery(value);
    const trimmed = value.trim();
    if (!trimmed) {
      setResults([]);
      setSearched(false);
      return;
    }
    setLoading(true);
    setSearched(true);
    const { data, error } = await supabase
      .from('notes')
      .select('*')
      .or(`content.ilike.%${trimmed}%,tags.cs.{${trimmed.toLowerCase()}}`)
      .order('created_at', { ascending: false })
      .limit(50);
    setLoading(false);
    if (!error) setResults(data ?? []);
  };

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Search</Text>
      <TextInput
        style={styles.input}
        placeholder="Search by keyword or tag"
        value={query}
        onChangeText={runSearch}
        autoCapitalize="none"
      />

      {loading && <ActivityIndicator style={styles.indicator} />}

      <FlatList
        data={results}
        keyExtractor={(item) => item.id}
        renderItem={({ item }) => (
          <View style={styles.noteRow}>
            <Text style={styles.noteType}>
              {item.type}
              {item.tags.length > 0 ? ` · ${item.tags.join(', ')}` : ''}
            </Text>
            <Text style={styles.noteContent} numberOfLines={3}>
              {item.type === 'text' ? item.content : `(${item.type} attachment)`}
            </Text>
          </View>
        )}
        ListEmptyComponent={
          !loading && searched ? (
            <Text style={styles.emptyText}>No notes match "{query}".</Text>
          ) : null
        }
      />
    </View>
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
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    borderRadius: 10,
    paddingHorizontal: 14,
    paddingVertical: 12,
    fontSize: 16,
    marginBottom: 16,
  },
  indicator: {
    marginBottom: 12,
  },
  noteRow: {
    paddingVertical: 10,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
  },
  noteType: {
    fontSize: 12,
    color: '#999',
    textTransform: 'uppercase',
    marginBottom: 2,
  },
  noteContent: {
    fontSize: 15,
  },
  emptyText: {
    color: '#999',
    marginTop: 20,
    textAlign: 'center',
  },
});
