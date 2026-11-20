import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Linking,
  Modal,
  NativeModules,
  NativeEventEmitter,
  Pressable,
  requireNativeComponent,
  Share,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
  type ViewProps,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';

const CameraView = requireNativeComponent<ViewProps>('ARCaptureView');
const Engine = NativeModules.ARCaptureEngine;
const Archive = NativeModules.ArchiveModule;
type Status = {
  recording?: boolean;
  finalizing?: boolean;
  sessionId?: string;
  name?: string;
  tracking?: string;
  trackingReason?: string;
  lidarAvailable?: boolean;
  depthAvailable?: boolean;
  elapsedSeconds?: number;
  framesWritten?: number;
  depthFrames?: number;
  videoFrames?: number;
  droppedFrames?: number;
  bytesWritten?: number;
  lastError?: string;
  measurement?: {
    pointCount?: number;
    distanceMeters?: number;
    verticalMeters?: number;
    points?: { depthMeters?: number; confidence?: number }[];
  };
};
type Session = {
  id: string;
  name: string;
  createdAt: string;
  durationSeconds: number;
  sizeBytes: number;
  finalized: boolean;
};
const C = {
  bg: '#071426',
  card: '#102239',
  line: '#24415A',
  cyan: '#27E4EF',
  coral: '#FF795F',
  text: '#F3F8FD',
  muted: '#A6BACD',
};
const errorText = (e: unknown) => (e instanceof Error ? e.message : String(e));
const duration = (s = 0) =>
  `${Math.floor(s / 60)
    .toString()
    .padStart(2, '0')}:${Math.floor(s % 60)
    .toString()
    .padStart(2, '0')}`;
const fileSize = (b = 0) => `${(b / 1048576).toFixed(1)} MB`;

function CaptureApp() {
  const inset = useSafeAreaInsets();
  const [tab, setTab] = useState<'capture' | 'sessions'>('capture');
  const [status, setStatus] = useState<Status>({});
  const [name, setName] = useState('Field walk');
  const [busy, setBusy] = useState(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [noteOpen, setNoteOpen] = useState(false);
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState('camera');
  const recordingRef = useRef(false);
  recordingRef.current = Boolean(status.recording);
  const refresh = useCallback(async () => {
    if (Engine) {
      try {
        setStatus(await Engine.getStatus());
      } catch {
        /* retry at next event */
      }
    }
  }, []);
  const refreshSessions = useCallback(async () => {
    try {
      setSessions(await Engine.listSessions());
    } catch (e) {
      Alert.alert('Sessions', errorText(e));
    }
  }, []);
  useEffect(() => {
    const subscription = Engine
      ? new NativeEventEmitter(Engine).addListener('ARCaptureStatus', setStatus)
      : undefined;
    refresh();
    const interval = setInterval(refresh, 2000);
    return () => {
      subscription?.remove();
      clearInterval(interval);
    };
  }, [refresh]);
  useEffect(() => {
    const handle = async (url: string) => {
      if (url.startsWith('aprilfoolsar://capture/start')) {
        setTab('capture');
        setTimeout(async () => {
          try {
            if (!recordingRef.current) {
              await Engine.startSession('Device capture check');
              await refresh();
            }
          } catch (e) {
            Alert.alert('Capture', errorText(e));
          }
        }, 1200);
      } else if (url.startsWith('aprilfoolsar://capture/stop')) {
        try {
          if (recordingRef.current) {
            await Engine.stopSession();
          }
          await refresh();
        } catch (e) {
          Alert.alert('Capture', errorText(e));
        }
      }
    };
    const sub = Linking.addEventListener('url', ({ url }) => handle(url));
    Linking.getInitialURL().then(url => {
      if (url) {
        handle(url);
      }
    });
    return () => sub.remove();
  }, [refresh]);
  const toggle = async () => {
    setBusy(true);
    try {
      if (status.recording) {
        await Engine.stopSession();
      } else {
        await Engine.startSession(name.trim() || 'Field walk');
      }
      await refresh();
    } catch (e) {
      Alert.alert('Recording', errorText(e));
    } finally {
      setBusy(false);
    }
  };
  const exportSession = async (session: Session) => {
    setBusy(true);
    try {
      const data = await Engine.exportSession(session.id);
      if (!data.finalized) {
        throw new Error('Stop and save the recording before exporting.');
      }
      const zip = await Archive.archiveSession(data.folderPath);
      await Share.share({
        url: zip.url,
        title: `April Fools AR — ${session.name}`,
      });
    } catch (e) {
      Alert.alert('Export', errorText(e));
    } finally {
      setBusy(false);
    }
  };
  const bookmark = async () => {
    try {
      await Engine.addBookmark(note.trim() || 'Field observation');
      setNote('');
      setNoteOpen(false);
    } catch (e) {
      Alert.alert('Bookmark', errorText(e));
    }
  };
  const setMode = async (mode: string) => {
    try {
      await Engine.setPreviewMode(mode);
      setPreview(mode);
    } catch (e) {
      Alert.alert('Preview', errorText(e));
    }
  };
  const m = status.measurement;
  const firstDepth = m?.points?.[0]?.depthMeters;
  const working = busy || status.finalizing;

  return (
    <View style={s.root}>
      <StatusBar barStyle="light-content" />
      <View style={[s.header, { paddingTop: inset.top + 9 }]}>
        <View style={s.brandRow}>
          <View style={s.mark}>
            <Text style={s.markText}>⌖</Text>
          </View>
          <View>
            <Text style={s.brand}>APRIL FOOLS AR</Text>
            <Text style={s.kicker}>FIELD CAPTURE · MILESTONE ZERO</Text>
          </View>
        </View>
        <View style={s.tabs}>
          {(['capture', 'sessions'] as const).map(t => (
            <Pressable
              key={t}
              style={[s.tab, tab === t && s.tabActive]}
              accessibilityRole="tab"
              accessibilityState={{ selected: tab === t }}
              onPress={() => {
                if (!status.recording && !working) {
                  setTab(t);
                  if (t === 'sessions') {
                    refreshSessions();
                  }
                }
              }}
            >
              <Text style={[s.tabText, tab === t && s.cyan]}>
                {t === 'capture' ? 'Live capture' : 'Saved sessions'}
              </Text>
            </Pressable>
          ))}
        </View>
      </View>
      {tab === 'capture' ? (
        <>
          <View style={s.camera}>
            {Engine ? (
              <CameraView style={StyleSheet.absoluteFill} />
            ) : (
              <Text style={s.failure}>Native capture module unavailable.</Text>
            )}
            <View style={s.cameraTop} pointerEvents="box-none">
              <View style={s.row}>
                <View style={s.pill}>
                  <View
                    style={[
                      s.dot,
                      {
                        backgroundColor:
                          status.tracking === 'normal' ? C.cyan : C.coral,
                      },
                    ]}
                  />
                  <Text style={s.pillText}>
                    {(status.tracking || 'STARTING').toUpperCase()}
                  </Text>
                </View>
                <View style={s.pill}>
                  <Text style={s.pillText}>
                    {status.depthAvailable
                      ? 'DEPTH LIVE'
                      : status.lidarAvailable
                      ? 'DEPTH WAITING'
                      : 'CHECKING LiDAR'}
                  </Text>
                </View>
              </View>
              {!!status.trackingReason && (
                <Text style={s.trackingHint}>
                  {status.trackingReason.replace(/([A-Z])/g, ' $1')}
                </Text>
              )}
              <View style={s.modes}>
                {['camera', 'depth', 'confidence'].map(mode => (
                  <Pressable
                    key={mode}
                    style={[s.mode, preview === mode && s.modeActive]}
                    onPress={() => setMode(mode)}
                  >
                    <Text style={[s.modeText, preview === mode && s.dark]}>
                      {mode === 'camera'
                        ? 'RGB'
                        : mode === 'depth'
                        ? 'Depth'
                        : 'Confidence'}
                    </Text>
                  </Pressable>
                ))}
              </View>
            </View>
            <View style={s.measure}>
              <View style={s.row}>
                <Text style={s.kicker}>TAP TWO SURFACES TO MEASURE</Text>
                <Pressable onPress={() => Engine.clearMeasurements()}>
                  <Text style={s.link}>Clear</Text>
                </Pressable>
              </View>
              <View style={s.values}>
                <View>
                  <Text style={s.value}>
                    {m?.distanceMeters != null
                      ? `${m.distanceMeters.toFixed(3)} m`
                      : '—'}
                  </Text>
                  <Text style={s.small}>3D distance</Text>
                </View>
                <View style={s.divider} />
                <View>
                  <Text style={s.value}>
                    {m?.verticalMeters != null
                      ? `${
                          m.verticalMeters >= 0 ? '+' : ''
                        }${m.verticalMeters.toFixed(3)} m`
                      : '—'}
                  </Text>
                  <Text style={s.small}>Vertical difference</Text>
                </View>
              </View>
              <Text style={s.hint}>
                {m?.pointCount === 1
                  ? `First point${
                      firstDepth != null
                        ? ` · ${firstDepth.toFixed(3)} m depth`
                        : ''
                    }. Tap the second surface.`
                  : 'AR/LiDAR estimates · Keep the phone steady when tapping.'}
              </Text>
            </View>
          </View>
          <View style={[s.controls, { paddingBottom: inset.bottom + 12 }]}>
            {status.lastError ? (
              <Text numberOfLines={2} style={s.failure}>
                {status.lastError}
              </Text>
            ) : (
              <View style={s.row}>
                <Text style={s.telemetry}>
                  {status.recording
                    ? '● RECORDING'
                    : status.depthAvailable
                    ? 'READY TO RECORD'
                    : 'WAITING FOR LIVE DEPTH'}
                </Text>
                <Text style={s.telemetry}>
                  {duration(status.elapsedSeconds)} ·{' '}
                  {status.framesWritten || 0} frames · {status.depthFrames || 0}{' '}
                  depth · {status.droppedFrames || 0} skipped
                </Text>
              </View>
            )}
            {!status.recording && (
              <TextInput
                accessibilityLabel="Session name"
                value={name}
                onChangeText={setName}
                style={s.input}
                placeholder="Session name"
                placeholderTextColor={C.muted}
                returnKeyType="done"
              />
            )}
            <View style={s.recordRow}>
              <Pressable
                onPress={toggle}
                disabled={working || !Engine}
                style={s.record}
                accessibilityLabel={
                  status.recording
                    ? 'Stop and save recording'
                    : 'Start recording'
                }
              >
                {working ? (
                  <ActivityIndicator color={C.bg} />
                ) : (
                  <>
                    <View style={[s.recordDot, status.recording && s.square]} />
                    <Text style={s.recordText}>
                      {status.recording ? 'Stop & save' : 'Start recording'}
                    </Text>
                  </>
                )}
              </Pressable>
              <Pressable
                onPress={() => setNoteOpen(true)}
                disabled={!status.recording || working}
                style={[s.bookmark, !status.recording && s.dim]}
              >
                <Text style={s.plus}>＋</Text>
                <Text style={s.bookmarkText}>Bookmark</Text>
              </Pressable>
            </View>
          </View>
        </>
      ) : (
        <View style={s.sessionPage}>
          <View style={s.row}>
            <Text style={s.title}>Your field recordings</Text>
            <Pressable onPress={refreshSessions}>
              <Text style={s.link}>Refresh</Text>
            </Pressable>
          </View>
          <Text style={s.description}>
            Export RGB video, numeric depth, poses, measurements, and notes in
            one ZIP.
          </Text>
          <FlatList
            data={sessions}
            keyExtractor={item => item.id}
            contentContainerStyle={s.list}
            ListEmptyComponent={
              <View style={s.empty}>
                <Text style={s.emptyMark}>⌖</Text>
                <Text style={s.title}>Ready for the first walk</Text>
                <Text style={s.description}>
                  Start a capture, walk the field, then stop to save your
                  session here.
                </Text>
              </View>
            }
            renderItem={({ item }) => (
              <View style={s.session}>
                <Text style={s.title}>{item.name}</Text>
                <Text style={s.description}>
                  {new Date(item.createdAt).toLocaleString()}
                </Text>
                <View style={s.row}>
                  <Text style={s.description}>
                    {duration(item.durationSeconds)} ·{' '}
                    {fileSize(item.sizeBytes)}
                  </Text>
                  <Pressable
                    disabled={busy}
                    style={s.export}
                    onPress={() => exportSession(item)}
                  >
                    {busy ? (
                      <ActivityIndicator color={C.bg} />
                    ) : (
                      <Text style={s.exportText}>Export ZIP ↗</Text>
                    )}
                  </Pressable>
                </View>
              </View>
            )}
          />
        </View>
      )}
      <Modal
        visible={noteOpen}
        transparent
        animationType="fade"
        onRequestClose={() => setNoteOpen(false)}
      >
        <View style={s.backdrop}>
          <View style={s.modal}>
            <Text style={s.title}>Mark this moment</Text>
            <Text style={s.description}>
              Tag ID, reference value, or an observation. A source image is
              saved with the bookmark.
            </Text>
            <TextInput
              autoFocus
              multiline
              value={note}
              onChangeText={setNote}
              placeholder="Tag 4 · floor at base · depth flickered…"
              placeholderTextColor={C.muted}
              style={s.noteInput}
            />
            <View style={s.row}>
              <Pressable onPress={() => setNoteOpen(false)}>
                <Text style={s.description}>Cancel</Text>
              </Pressable>
              <Pressable onPress={bookmark} style={s.export}>
                <Text style={s.exportText}>Save bookmark</Text>
              </Pressable>
            </View>
          </View>
        </View>
      </Modal>
    </View>
  );
}

export default function App() {
  return (
    <SafeAreaProvider>
      <CaptureApp />
    </SafeAreaProvider>
  );
}

const s = StyleSheet.create({
  root: { flex: 1, backgroundColor: C.bg },
  header: { paddingHorizontal: 20 },
  brandRow: { flexDirection: 'row', gap: 11, alignItems: 'center' },
  mark: {
    width: 39,
    height: 39,
    borderWidth: 1.5,
    borderColor: C.cyan,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },
  markText: { fontSize: 29, color: C.cyan },
  brand: { color: C.text, fontSize: 18, fontWeight: '800', letterSpacing: 1.4 },
  kicker: {
    color: C.muted,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 1.2,
    marginTop: 4,
  },
  tabs: { flexDirection: 'row', gap: 24, marginTop: 18 },
  tab: {
    paddingBottom: 11,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: C.cyan },
  tabText: { color: C.muted, fontSize: 13, fontWeight: '600' },
  cyan: { color: C.cyan },
  dark: { color: C.bg },
  camera: { flex: 1, backgroundColor: C.card, overflow: 'hidden' },
  cameraTop: { position: 'absolute', top: 14, left: 15, right: 15 },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  pill: {
    backgroundColor: '#071426DB',
    paddingHorizontal: 11,
    paddingVertical: 8,
    borderRadius: 16,
    flexDirection: 'row',
    gap: 7,
    alignItems: 'center',
  },
  pillText: {
    fontSize: 9,
    color: C.text,
    fontWeight: '700',
    letterSpacing: 0.6,
  },
  dot: { width: 6, height: 6, borderRadius: 3 },
  trackingHint: {
    color: C.text,
    backgroundColor: '#071426DB',
    alignSelf: 'flex-start',
    paddingHorizontal: 11,
    paddingVertical: 5,
    borderRadius: 8,
    marginTop: 6,
    fontSize: 11,
  },
  modes: {
    flexDirection: 'row',
    padding: 3,
    backgroundColor: '#071426DD',
    borderRadius: 20,
    alignSelf: 'center',
    marginTop: 12,
  },
  mode: { paddingVertical: 8, paddingHorizontal: 14, borderRadius: 17 },
  modeActive: { backgroundColor: C.cyan },
  modeText: { fontSize: 11, fontWeight: '600', color: C.text },
  measure: {
    position: 'absolute',
    bottom: 14,
    left: 14,
    right: 14,
    backgroundColor: '#071426E8',
    borderWidth: 1,
    borderColor: '#52697977',
    borderRadius: 18,
    padding: 15,
  },
  link: { fontSize: 12, fontWeight: '600', color: C.cyan },
  values: {
    flexDirection: 'row',
    gap: 23,
    alignItems: 'center',
    marginTop: 10,
  },
  value: {
    color: C.text,
    fontSize: 24,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  small: { color: C.muted, fontSize: 10, marginTop: 4 },
  divider: { width: 1, height: 33, backgroundColor: C.line },
  hint: { fontSize: 10, color: C.muted, marginTop: 12 },
  controls: { paddingHorizontal: 18, paddingTop: 13 },
  telemetry: {
    fontSize: 9,
    color: C.muted,
    fontVariant: ['tabular-nums'],
    marginBottom: 11,
  },
  input: {
    height: 39,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: C.line,
    paddingHorizontal: 12,
    color: C.text,
    fontSize: 13,
    marginBottom: 11,
  },
  recordRow: { flexDirection: 'row', gap: 11 },
  record: {
    flex: 1,
    height: 53,
    borderRadius: 13,
    backgroundColor: C.coral,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 10,
  },
  recordText: { fontSize: 15, fontWeight: '800', color: C.bg },
  recordDot: { width: 13, height: 13, borderRadius: 7, backgroundColor: C.bg },
  square: { borderRadius: 3 },
  bookmark: {
    minWidth: 86,
    backgroundColor: C.card,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  plus: { color: C.cyan, fontSize: 20, lineHeight: 22 },
  bookmarkText: { color: C.text, fontSize: 10, marginTop: 2 },
  dim: { opacity: 0.4 },
  failure: { color: '#FFAB95', fontSize: 11, marginBottom: 10 },
  sessionPage: { flex: 1, paddingHorizontal: 20, paddingTop: 24 },
  title: { color: C.text, fontSize: 18, fontWeight: '700' },
  description: { color: C.muted, fontSize: 12, lineHeight: 19, marginTop: 8 },
  list: { paddingTop: 18, paddingBottom: 35, gap: 12 },
  session: {
    backgroundColor: C.card,
    borderWidth: 1,
    borderColor: C.line,
    borderRadius: 17,
    padding: 17,
    gap: 6,
  },
  export: {
    backgroundColor: C.cyan,
    paddingVertical: 10,
    paddingHorizontal: 13,
    borderRadius: 9,
  },
  exportText: { color: C.bg, fontSize: 12, fontWeight: '800' },
  empty: { alignItems: 'center', paddingTop: 45, gap: 9 },
  emptyMark: { fontSize: 48, color: C.cyan },
  backdrop: {
    flex: 1,
    backgroundColor: '#000000AA',
    padding: 23,
    justifyContent: 'center',
  },
  modal: { backgroundColor: C.card, padding: 22, borderRadius: 21, gap: 14 },
  noteInput: {
    minHeight: 100,
    borderWidth: 1,
    borderColor: C.line,
    borderRadius: 12,
    padding: 13,
    color: C.text,
    fontSize: 14,
  },
});
