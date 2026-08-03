import { useCallback, useEffect, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  Platform,
  Pressable,
  RefreshControl,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import * as Calendar from 'expo-calendar';
import { supabase } from '../lib/supabase';
import type { Note, Task } from '../lib/types';

interface BriefingEvent {
  id: string;
  title: string;
  startDate: Date;
  allDay: boolean;
}

interface BriefingReminder {
  id: string;
  title: string;
}

export default function PlanningScreen() {
  const [events, setEvents] = useState<BriefingEvent[]>([]);
  const [reminders, setReminders] = useState<BriefingReminder[]>([]);
  const [tasks, setTasks] = useState<Task[]>([]);
  const [recentNotes, setRecentNotes] = useState<Note[]>([]);
  const [loading, setLoading] = useState(true);
  const [calendarAvailable, setCalendarAvailable] = useState(true);

  const loadBriefing = useCallback(async () => {
    setLoading(true);

    const startOfDay = new Date();
    startOfDay.setHours(0, 0, 0, 0);
    const endOfDay = new Date();
    endOfDay.setHours(23, 59, 59, 999);

    try {
      const calendarPermission = await Calendar.requestCalendarPermissions();
      if (calendarPermission.granted) {
        const calendars = await Calendar.getCalendars(Calendar.EntityTypes.EVENT);
        const rawEvents = await Calendar.listEvents(calendars, startOfDay, endOfDay);
        setEvents(
          rawEvents
            .map((e) => ({
              id: e.id,
              title: e.title,
              startDate: new Date(e.startDate),
              allDay: e.allDay,
            }))
            .sort((a, b) => a.startDate.getTime() - b.startDate.getTime()),
        );
        setCalendarAvailable(true);
      } else {
        setCalendarAvailable(false);
      }

      if (Platform.OS === 'ios') {
        const reminderPermission = await Calendar.requestRemindersPermissions();
        if (reminderPermission.granted) {
          const reminderCalendars = await Calendar.getCalendars(Calendar.EntityTypes.REMINDER);
          const allReminders: BriefingReminder[] = [];
          for (const cal of reminderCalendars) {
            const list = await cal.listReminders(null, null, Calendar.ReminderStatus.INCOMPLETE);
            allReminders.push(
              ...list
                .filter((r): r is typeof r & { id: string; title: string } => !!r.id && !!r.title)
                .map((r) => ({ id: r.id, title: r.title })),
            );
          }
          setReminders(allReminders);
        }
      }
    } catch (err) {
      Alert.alert('Could not load calendar', (err as Error).message);
    }

    const [{ data: taskData }, { data: noteData }] = await Promise.all([
      supabase
        .from('tasks')
        .select('*')
        .eq('completed', false)
        .order('created_at', { ascending: false })
        .limit(20),
      supabase.from('notes').select('*').order('created_at', { ascending: false }).limit(5),
    ]);

    setTasks(taskData ?? []);
    setRecentNotes(noteData ?? []);
    setLoading(false);
  }, []);

  useEffect(() => {
    loadBriefing();
  }, [loadBriefing]);

  const completeTask = async (taskId: string) => {
    setTasks((prev) => prev.filter((t) => t.id !== taskId));
    await supabase.from('tasks').update({ completed: true }).eq('id', taskId);
  };

  return (
    <ScrollView
      style={styles.container}
      refreshControl={<RefreshControl refreshing={loading} onRefresh={loadBriefing} />}
    >
      <Text style={styles.heading}>Daily Briefing</Text>

      <Text style={styles.sectionHeading}>Today's calendar</Text>
      {!calendarAvailable && (
        <Text style={styles.mutedText}>Calendar access not granted.</Text>
      )}
      {events.length === 0 && calendarAvailable && !loading && (
        <Text style={styles.mutedText}>Nothing scheduled today.</Text>
      )}
      {events.map((event) => (
        <View key={event.id} style={styles.row}>
          <Text style={styles.rowMeta}>
            {event.allDay
              ? 'All day'
              : event.startDate.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
          </Text>
          <Text style={styles.rowTitle}>{event.title}</Text>
        </View>
      ))}

      {Platform.OS === 'ios' && (
        <>
          <Text style={styles.sectionHeading}>Reminders</Text>
          {reminders.length === 0 && !loading && (
            <Text style={styles.mutedText}>No open reminders.</Text>
          )}
          {reminders.map((reminder) => (
            <View key={reminder.id} style={styles.row}>
              <Text style={styles.rowTitle}>{reminder.title}</Text>
            </View>
          ))}
        </>
      )}

      <Text style={styles.sectionHeading}>Open tasks from notes</Text>
      {tasks.length === 0 && !loading && (
        <Text style={styles.mutedText}>No open action items.</Text>
      )}
      {tasks.map((task) => (
        <Pressable key={task.id} style={styles.taskRow} onPress={() => completeTask(task.id)}>
          <Text style={styles.checkbox}>{'○'}</Text>
          <Text style={styles.rowTitle}>{task.description}</Text>
        </Pressable>
      ))}

      <Text style={styles.sectionHeading}>Recent notes</Text>
      {recentNotes.map((note) => (
        <View key={note.id} style={styles.row}>
          <Text style={styles.rowMeta}>{new Date(note.created_at).toLocaleDateString()}</Text>
          <Text style={styles.rowTitle} numberOfLines={1}>
            {note.type === 'text' ? note.content : `(${note.type} note)`}
          </Text>
        </View>
      ))}

      {loading && <ActivityIndicator style={styles.indicator} />}
      <View style={styles.bottomSpacer} />
    </ScrollView>
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
  sectionHeading: {
    fontSize: 16,
    fontWeight: '600',
    color: '#555',
    marginTop: 24,
    marginBottom: 8,
    textTransform: 'uppercase',
  },
  row: {
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
  },
  rowMeta: {
    fontSize: 12,
    color: '#999',
    marginBottom: 2,
  },
  rowTitle: {
    fontSize: 15,
  },
  taskRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingVertical: 8,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: '#ddd',
  },
  checkbox: {
    fontSize: 18,
    color: '#666',
  },
  mutedText: {
    color: '#999',
  },
  indicator: {
    marginTop: 20,
  },
  bottomSpacer: {
    height: 40,
  },
});
