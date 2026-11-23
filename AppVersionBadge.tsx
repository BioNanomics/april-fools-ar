import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

export type AppVersion = { version: string; build: string };

export function AppVersionBadge({
  info,
  onPress,
}: {
  info?: AppVersion | null;
  onPress?: () => void;
}) {
  const inset = useSafeAreaInsets();
  const version = info
    ? `Version ${info.version}, build ${info.build}`
    : 'Loading';
  const label = (
    <Text
      accessible={!onPress}
      accessibilityLabel="Installed app version"
      accessibilityValue={{ text: version }}
      style={s.text}
    >
      {info ? `v${info.version} (${info.build})` : 'Version…'}
    </Text>
  );
  if (onPress) {
    return (
      <Pressable
        testID="app.versionBadge"
        accessibilityRole="button"
        accessibilityLabel="Open version and release notes"
        accessibilityValue={{ text: version }}
        onPress={onPress}
        style={[
          s.badge,
          s.button,
          { top: inset.top + 8, right: inset.right + 12 },
        ]}
      >
        {label}
      </Pressable>
    );
  }
  return (
    <View
      testID="app.versionBadge"
      pointerEvents="none"
      style={[s.badge, { top: inset.top + 8, right: inset.right + 12 }]}
    >
      {label}
    </View>
  );
}

const s = StyleSheet.create({
  badge: {
    position: 'absolute',
    zIndex: 10,
    paddingHorizontal: 6,
    paddingVertical: 4,
    borderRadius: 6,
    backgroundColor: '#071426DB',
  },
  button: { minHeight: 44, minWidth: 84, justifyContent: 'center' },
  text: {
    color: '#A6BACD',
    fontSize: 10,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
});
