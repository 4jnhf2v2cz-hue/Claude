import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { Audio } from 'expo-av';
import { File } from 'expo-file-system';
import { supabase } from '../lib/supabase';
import type { Note } from '../lib/types';
import { useAuth } from '../context/AuthContext';

export default function CaptureScreen() {
  const { session } = useAuth();
  const userId = session?.user.id;

  const [text, setText] = useState('');
  const [saving, setSaving] = useState(false);
  const [recording, setRecording] = useState<Audio.Recording | null>(null);
  const [isRecording, setIsRecording] = useState(false);
  const [notes, setNotes] = useState<Note[]>([]);
  const [loadingNotes, setLoadingNotes] = useState(true);

  const loadNotes = useCallback(async () => {
    if (!userId) return;
    setLoadingNotes(true);
    const { data, error } = await supabase
      .from('notes')
      .select('*')
      .order('created_at', { ascending: false })
      .limit(50);
    setLoadingNotes(false);
    if (error) {
      Alert.alert('Failed to load notes', error.message);
      return;
    }
    setNotes(data ?? []);
  }, [userId]);

  useEffect(() => {
    loadNotes();
  }, [loadNotes]);

  const saveTextNote = async () => {
    if (!userId || !text.trim()) return;
    setSaving(true);
    const { error } = await supabase.from('notes').insert({
      user_id: userId,
      content: text.trim(),
      type: 'text',
      tags: [],
      source: 'app',
    });
    setSaving(false);
    if (error) {
      Alert.alert('Failed to save note', error.message);
      return;
    }
    setText('');
    loadNotes();
  };

  const startRecording = async () => {
    try {
      const permission = await Audio.requestPermissionsAsync();
      if (!permission.granted) {
        Alert.alert('Microphone permission is required to record voice memos.');
        return;
      }
      await Audio.setAudioModeAsync({ allowsRecordingIOS: true, playsInSilentModeIOS: true });
      const { recording: newRecording } = await Audio.Recording.createAsync(
        Audio.RecordingOptionsPresets.HIGH_QUALITY
      );
      setRecording(newRecording);
      setIsRecording(true);
    } catch (err) {
      Alert.alert('Could not start recording', (err as Error).message);
    }
  };

  const stopRecording = async () => {
    if (!recording || !userId) return;
    setIsRecording(false);
    setSaving(true);
    try {
      await recording.stopAndUnloadAsync();
      await Audio.setAudioModeAsync({ allowsRecordingIOS: false });
      const uri = recording.getURI();
      setRecording(null);
      if (!uri) throw new Error('Recording produced no file.');

      const file = new File(uri);
      if (!file.exists) throw new Error('Recording file not found.');

      const fileBuffer = await file.arrayBuffer();
      const path = `${userId}/${Date.now()}.m4a`;

      const { error: uploadError } = await supabase.storage
        .from('note-attachments')
        .upload(path, fileBuffer, { contentType: 'audio/m4a' });
      if (uploadError) throw uploadError;

      const { error: insertError } = await supabase.from('notes').insert({
        user_id: userId,
        content: '',
        type: 'voice',
        tags: [],
        source: path,
      });
      if (insertError) throw insertError;

      loadNotes();
    } catch (err) {
      Alert.alert('Failed to save voice memo', (err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.heading}>Capture</Text>

      <TextInput
        style={styles.input}
        placeholder="What's on your mind?"
        multiline
        value={text}
        onChangeText={setText}
      />

      <View style={styles.row}>
        <Pressable
          style={[styles.button, (!text.trim() || saving) && styles.buttonDisabled]}
          onPress={saveTextNote}
          disabled={!text.trim() || saving}
        >
          <Text style={styles.buttonText}>Save Note</Text>
        </Pressable>

        <Pressable
          style={[styles.button, styles.recordButton, isRecording && styles.recordingActive]}
          onPress={isRecording ? stopRecording : startRecording}
          disabled={saving && !isRecording}
        >
          <Text style={styles.buttonText}>{isRecording ? 'Stop' : 'Record'}</Text>
        </Pressable>
      </View>

      {saving && <ActivityIndicator style={styles.savingIndicator} />}

      <Text style={styles.listHeading}>Recent notes</Text>
      {loadingNotes ? (
        <ActivityIndicator />
      ) : (
        <FlatList
          data={notes}
          keyExtractor={(item) => item.id}
          renderItem={({ item }) => (
            <View style={styles.noteRow}>
              <Text style={styles.noteType}>{item.type}</Text>
              <Text style={styles.noteContent} numberOfLines={2}>
                {item.type === 'voice' ? '(voice memo)' : item.content}
              </Text>
            </View>
          )}
          ListEmptyComponent={<Text style={styles.emptyText}>No notes yet — capture your first one above.</Text>}
        />
      )}
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
    padding: 14,
    fontSize: 16,
    minHeight: 90,
    textAlignVertical: 'top',
  },
  row: {
    flexDirection: 'row',
    gap: 12,
    marginTop: 12,
  },
  button: {
    flex: 1,
    backgroundColor: '#111',
    borderRadius: 10,
    paddingVertical: 14,
    alignItems: 'center',
  },
  buttonDisabled: {
    opacity: 0.4,
  },
  recordButton: {
    backgroundColor: '#b33',
  },
  recordingActive: {
    backgroundColor: '#700',
  },
  buttonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  savingIndicator: {
    marginTop: 12,
  },
  listHeading: {
    fontSize: 18,
    fontWeight: '600',
    marginTop: 28,
    marginBottom: 8,
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
