import { useEffect, useRef } from 'react';
import { ActivityIndicator, Alert, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import * as Linking from 'expo-linking';
import { NavigationContainer } from '@react-navigation/native';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { AuthProvider, useAuth } from './context/AuthContext';
import SignInScreen from './screens/SignInScreen';
import CaptureScreen from './screens/CaptureScreen';
import SearchScreen from './screens/SearchScreen';
import ChatScreen from './screens/ChatScreen';
import PlanningScreen from './screens/PlanningScreen';
import { quickCaptureText } from './lib/quickCapture';

const Tab = createBottomTabNavigator();

function useShortcutCapture(userId: string | undefined) {
  const pendingUrl = useRef<string | null>(null);

  useEffect(() => {
    const handleUrl = (url: string) => {
      const { hostname, path, queryParams } = Linking.parse(url);
      const isCapture = hostname === 'capture' || path === 'capture';
      const text = typeof queryParams?.text === 'string' ? queryParams.text : undefined;
      if (!isCapture || !text) return;

      if (!userId) {
        pendingUrl.current = url;
        return;
      }
      quickCaptureText(userId, text).catch((err) => {
        Alert.alert('Shortcut capture failed', (err as Error).message);
      });
    };

    Linking.getInitialURL().then((url) => {
      if (url) handleUrl(url);
    });
    const subscription = Linking.addEventListener('url', ({ url }) => handleUrl(url));
    return () => subscription.remove();
  }, [userId]);
}

function Root() {
  const { session, initializing } = useAuth();
  useShortcutCapture(session?.user.id);

  if (initializing) {
    return (
      <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
        <ActivityIndicator />
      </View>
    );
  }

  if (!session) return <SignInScreen />;

  return (
    <NavigationContainer>
      <Tab.Navigator screenOptions={{ headerShown: false }}>
        <Tab.Screen name="Capture" component={CaptureScreen} />
        <Tab.Screen name="Search" component={SearchScreen} />
        <Tab.Screen name="Recall" component={ChatScreen} />
        <Tab.Screen name="Plan" component={PlanningScreen} />
      </Tab.Navigator>
    </NavigationContainer>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <Root />
      <StatusBar style="auto" />
    </AuthProvider>
  );
}
