import React from 'react';
import {
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
  useWindowDimensions,
} from 'react-native';
import {
  SafeAreaView,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';

export type ReleaseNote = {
  version: string;
  build: string;
  title: string;
  changes: string[];
};

export type AppInfo = {
  bundleId: string;
  version: string;
  build: string;
  buildCommit: string;
  buildDateUTC: string;
  workingTreeDirty: boolean;
  releaseNotes: ReleaseNote[];
};

type Props = {
  visible: boolean;
  info: AppInfo | null;
  onClose: () => void;
};

const C = {
  bg: '#071426',
  card: '#102239',
  line: '#24415A',
  cyan: '#A1D18B',
  text: '#F3F8FD',
  muted: '#A6BACD',
  amber: '#FFD16A',
};

function humanUTC(value: string): string {
  const date = new Date(value);
  if (!Number.isFinite(date.getTime())) {
    return 'Build date unavailable';
  }
  return date.toISOString().replace('T', ' ').replace('Z', ' UTC');
}

function ReleaseCard({
  release,
  current = false,
}: {
  release: ReleaseNote;
  current?: boolean;
}) {
  return (
    <View
      style={[styles.release, current && styles.currentRelease]}
      testID={
        current
          ? 'current-release'
          : `release-${release.version}-${release.build}`
      }
    >
      <Text style={current ? styles.currentBadge : styles.releaseVersion}>
        {current
          ? 'CURRENT BUILD'
          : `Version ${release.version} · Build ${release.build}`}
      </Text>
      <Text style={styles.releaseTitle} accessibilityRole="header">
        {release.title}
      </Text>
      {release.changes.map((change, index) => (
        <View key={`${index}-${change}`} style={styles.change}>
          <Text style={styles.bullet}>•</Text>
          <Text style={styles.changeText}>{change}</Text>
        </View>
      ))}
    </View>
  );
}

export function ReleaseNotesModal({ visible, info, onClose }: Props) {
  const { width, height } = useWindowDimensions();
  const inset = useSafeAreaInsets();
  const compact = height < 500;
  const wide = width - inset.left - inset.right >= 800;
  if (!visible) {
    return null;
  }
  const current = info?.releaseNotes.find(
    release => release.version === info.version && release.build === info.build,
  );
  const history =
    info?.releaseNotes.filter(release => release !== current) ?? [];

  return (
    <Modal
      visible={visible}
      animationType="slide"
      transparent
      supportedOrientations={[
        'portrait',
        'landscape-left',
        'landscape-right',
        'portrait-upside-down',
      ]}
      onDismiss={onClose}
      onRequestClose={onClose}
    >
      <SafeAreaView
        style={[styles.backdrop, compact && styles.backdropCompact]}
        edges={['top', 'bottom', 'left', 'right']}
        accessibilityViewIsModal
      >
        <View style={styles.sheet}>
          <View style={[styles.header, compact && styles.headerCompact]}>
            <View style={styles.heading}>
              <Text style={styles.eyebrow}>APRIL FOOLS AR</Text>
              <Text
                style={[styles.title, compact && styles.titleCompact]}
                accessibilityRole="header"
              >
                Version & release notes
              </Text>
            </View>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Close release notes"
              onPress={onClose}
              style={styles.close}
            >
              <Text style={styles.closeText}>Done</Text>
            </Pressable>
          </View>

          <ScrollView
            style={styles.scroll}
            contentContainerStyle={styles.content}
            showsVerticalScrollIndicator
          >
            {info ? (
              <View style={[styles.columns, wide && styles.columnsWide]}>
                <View
                  style={[styles.buildCard, wide && styles.buildColumn]}
                  testID="installed-build-details"
                >
                  <Text style={styles.version}>Version {info.version}</Text>
                  <Text style={styles.build}>Build {info.build}</Text>
                  <Text style={styles.label}>Source revision</Text>
                  <Text selectable style={styles.commit}>
                    {info.buildCommit.slice(0, 12) || 'Unavailable'}
                  </Text>
                  <Text selectable style={styles.exactValue}>
                    {info.buildCommit || 'Full source revision unavailable'}
                  </Text>
                  <Text
                    style={[
                      styles.sourceState,
                      info.workingTreeDirty && styles.dirtySource,
                    ]}
                  >
                    {info.workingTreeDirty
                      ? 'UNCOMMITTED SOURCE CHANGES'
                      : 'Clean source tree'}
                  </Text>
                  <Text style={styles.label}>Built · UTC</Text>
                  <Text style={styles.value}>
                    {humanUTC(info.buildDateUTC)}
                  </Text>
                  <Text selectable style={styles.exactValue}>
                    {info.buildDateUTC || 'Exact build timestamp unavailable'}
                  </Text>
                  <Text style={styles.label}>App identifier</Text>
                  <Text selectable style={styles.exactValue}>
                    {info.bundleId}
                  </Text>
                </View>

                <View
                  style={[styles.notesColumn, wide && styles.notesColumnWide]}
                >
                  {current ? (
                    <ReleaseCard release={current} current />
                  ) : (
                    <View style={styles.release}>
                      <Text style={styles.changeText}>
                        No release notes are bundled for this installed version
                        and build.
                      </Text>
                    </View>
                  )}
                  {history.length > 0 && (
                    <>
                      <Text
                        style={styles.historyTitle}
                        accessibilityRole="header"
                      >
                        Release history
                      </Text>
                      {history.map(release => (
                        <ReleaseCard
                          key={`${release.version}-${release.build}`}
                          release={release}
                        />
                      ))}
                    </>
                  )}
                </View>
              </View>
            ) : (
              <View style={styles.release}>
                <Text style={styles.releaseTitle}>
                  Build information unavailable
                </Text>
                <Text style={styles.changeText}>
                  Close this view and reopen it to retry loading the installed
                  app details.
                </Text>
              </View>
            )}
          </ScrollView>
        </View>
      </SafeAreaView>
    </Modal>
  );
}

export default ReleaseNotesModal;

const styles = StyleSheet.create({
  backdrop: {
    flex: 1,
    backgroundColor: '#000000AA',
    padding: 20,
    justifyContent: 'center',
  },
  backdropCompact: { padding: 8 },
  sheet: {
    flex: 1,
    width: '100%',
    maxWidth: 980,
    maxHeight: 920,
    alignSelf: 'center',
    minHeight: 0,
    backgroundColor: C.bg,
    borderRadius: 20,
    overflow: 'hidden',
  },
  columns: { gap: 18 },
  columnsWide: { flexDirection: 'row', alignItems: 'flex-start' },
  buildColumn: { flex: 0.9, minWidth: 0 },
  notesColumn: { minWidth: 0, gap: 16 },
  notesColumnWide: { flex: 1.1 },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: C.line,
    gap: 12,
  },
  headerCompact: { paddingVertical: 8 },
  titleCompact: { fontSize: 19, marginTop: 2 },
  heading: { flex: 1, minWidth: 0 },
  eyebrow: {
    color: C.cyan,
    fontSize: 11,
    fontWeight: '700',
    letterSpacing: 1.2,
  },
  title: { color: C.text, fontSize: 22, fontWeight: '700', marginTop: 5 },
  close: {
    minWidth: 60,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 10,
    backgroundColor: C.card,
    borderWidth: 1,
    borderColor: C.line,
  },
  closeText: { color: C.cyan, fontSize: 16, fontWeight: '700' },
  scroll: { flex: 1, minHeight: 0 },
  content: { padding: 20, paddingBottom: 36, gap: 16 },
  buildCard: {
    backgroundColor: C.card,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: C.line,
    padding: 18,
  },
  version: { color: C.text, fontSize: 28, fontWeight: '700' },
  build: { color: C.cyan, fontSize: 19, fontWeight: '600', marginTop: 3 },
  label: {
    color: C.muted,
    fontSize: 12,
    fontWeight: '600',
    marginTop: 18,
    marginBottom: 5,
  },
  value: { color: C.text, fontSize: 15, lineHeight: 22 },
  commit: {
    color: C.text,
    fontFamily: 'Menlo',
    fontSize: 17,
    fontWeight: '600',
  },
  exactValue: {
    color: C.muted,
    fontFamily: 'Menlo',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 4,
  },
  sourceState: {
    color: C.muted,
    fontSize: 12,
    fontWeight: '600',
    marginTop: 9,
  },
  dirtySource: { color: C.amber },
  release: {
    backgroundColor: C.card,
    borderColor: C.line,
    borderWidth: 1,
    borderRadius: 14,
    padding: 18,
  },
  currentRelease: { borderColor: C.cyan, borderWidth: 2 },
  currentBadge: {
    color: C.cyan,
    fontSize: 11,
    fontWeight: '800',
    letterSpacing: 1,
  },
  releaseVersion: { color: C.muted, fontSize: 13, fontWeight: '600' },
  releaseTitle: {
    color: C.text,
    fontSize: 19,
    fontWeight: '700',
    lineHeight: 25,
    marginTop: 6,
    marginBottom: 8,
  },
  change: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: 9,
    marginTop: 8,
  },
  bullet: { color: C.cyan, fontSize: 17, lineHeight: 23 },
  changeText: { color: C.text, fontSize: 15, lineHeight: 23, flexShrink: 1 },
  historyTitle: {
    color: C.text,
    fontSize: 17,
    fontWeight: '700',
    marginTop: 8,
  },
});
