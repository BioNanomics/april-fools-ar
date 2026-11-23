import React, { useCallback, useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Alert,
  FlatList,
  Image,
  Linking,
  KeyboardAvoidingView,
  Keyboard,
  Platform,
  Modal,
  NativeModules,
  NativeEventEmitter,
  Pressable,
  requireNativeComponent,
  Share,
  ScrollView,
  StatusBar,
  StyleSheet,
  Text,
  TextInput,
  View,
  useWindowDimensions,
  type ViewProps,
} from 'react-native';
import {
  SafeAreaProvider,
  useSafeAreaInsets,
} from 'react-native-safe-area-context';
import {
  DebugSettingsModal,
  DEFAULT_DEBUG_SETTINGS,
  type DebugSettings,
} from './DebugSettingsModal';
import { ReleaseNotesModal, type AppInfo } from './ReleaseNotesModal';
import { formatHeight } from './HeightUnits';
import { AboutModal, type AboutPage } from './AboutModal';

const CameraView = requireNativeComponent<ViewProps>('ARCaptureView');
const Engine = NativeModules.ARCaptureEngine;
const Archive = NativeModules.ArchiveModule;
type Measurement = {
  kind?: string;
  pointCount?: number;
  distanceMeters?: number;
  verticalMeters?: number;
  heightMeters?: number;
  points?: { depthMeters?: number; confidence?: number }[];
};
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
  debugMode?: boolean;
  displayZoom?: number;
  previewMode?: string;
  spatial?: {
    mode?: 'distance' | 'height' | 'selectFloor' | 'tagWidth';
    showFloorPlanes?: boolean;
    floorSelected?: boolean;
    floorId?: string;
    floorTiltDegrees?: number | null;
    levelFloorWithGravity?: boolean;
    candidateCount?: number;
    measurementCount?: number;
    lastMeasurement?: Measurement | null;
    floorSetup?: {
      active?: boolean;
      candidateSelected?: boolean;
      candidateId?: string;
      areaSquareMeters?: number;
      minSpanMeters?: number;
      ready?: boolean;
      reason?: string;
    };
  };
  aprilTag?: {
    state?:
      | 'initializing'
      | 'waiting'
      | 'ready'
      | 'running'
      | 'paused'
      | 'error';
    family?: string;
    ids?: number[];
    count?: number;
    latencyMilliseconds?: number;
    analyzedFrames?: number;
    skippedFrames?: number;
    error?: string;
    analysisHz?: number;
    debugSettings?: DebugSettings;
  };
  measurement?: Measurement;
};
type Session = {
  id: string;
  name: string;
  createdAt: string;
  durationSeconds: number;
  sizeBytes: number;
  finalized: boolean;
  recordingReady?: boolean;
  recordingBytes?: number;
  recordingError?: string;
};
const C = {
  bg: '#071426',
  card: '#102239',
  line: '#24415A',
  cyan: '#A1D18B',
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
  const { width, height } = useWindowDimensions();
  const usableWidth = width - inset.left - inset.right;
  const tablet = Math.min(width, height) >= 600;
  const landscape = width > height;
  const wide =
    (landscape && usableWidth >= 620) || (tablet && usableWidth >= 740);
  const compactLandscape = wide && height < 500;
  const railWidth = tablet && !compactLandscape ? 336 : 276;
  const sessionColumns = usableWidth >= 1050 ? 3 : usableWidth >= 680 ? 2 : 1;
  const sessionCardWidth =
    (Math.min(width, 1440) -
      inset.left -
      inset.right -
      40 -
      14 * (sessionColumns - 1)) /
    sessionColumns;
  const [tab, setTab] = useState<'capture' | 'sessions'>('capture');
  const [status, setStatus] = useState<Status>({});
  const [name, setName] = useState('Field walk');
  const [editingName, setEditingName] = useState(false);
  const [busy, setBusy] = useState(false);
  const [sessionAction, setSessionAction] = useState<{
    id: string;
    action: 'play' | 'share';
  } | null>(null);
  const sessionActionRef = useRef(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const [noteOpen, setNoteOpen] = useState(false);
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState('camera');
  const [appInfo, setAppInfo] = useState<AppInfo | null>(null);
  const [releaseNotesOpen, setReleaseNotesOpen] = useState(false);
  const [aboutOpen, setAboutOpen] = useState(false);
  const [aboutPage, setAboutPage] = useState<AboutPage>('privacy');
  const [debugEnabled, setDebugEnabled] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [measuringTagSize, setMeasuringTagSize] = useState(false);
  const [finishingFloor, setFinishingFloor] = useState(false);
  const [debugSettings, setDebugSettings] = useState<DebugSettings>(
    DEFAULT_DEBUG_SETTINGS,
  );
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
    let active = true;
    Engine?.getAppInfo()
      .then((info: AppInfo) => {
        if (active) {
          setAppInfo(info);
        }
      })
      .catch(() => {
        /* The version button retries if native metadata is unavailable. */
      });
    return () => {
      active = false;
    };
  }, []);
  useEffect(() => {
    if (typeof status.debugMode === 'boolean') {
      setDebugEnabled(status.debugMode);
    }
  }, [status.debugMode]);
  useEffect(() => {
    if (status.previewMode) {
      setPreview(status.previewMode);
    }
  }, [status.previewMode]);
  useEffect(() => {
    const enabled = status.aprilTag?.debugSettings?.showImperialHeight;
    if (typeof enabled === 'boolean') {
      setDebugSettings(previous =>
        previous.showImperialHeight === enabled
          ? previous
          : { ...previous, showImperialHeight: enabled },
      );
    }
  }, [status.aprilTag?.debugSettings?.showImperialHeight]);
  useEffect(() => {
    const handle = async (url: string) => {
      if (url.startsWith('aprilfoolsar://capture/start')) {
        if (sessionActionRef.current) {
          return;
        }
        setTab('capture');
        setTimeout(async () => {
          try {
            if (!recordingRef.current && !sessionActionRef.current) {
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
    Keyboard.dismiss();
    setEditingName(false);
    setBusy(true);
    try {
      if (status.recording) {
        const saved = await Engine.stopSession();
        if (saved?.recordingReady === false && saved.recordingError) {
          Alert.alert(
            'Recording saved',
            `The original recording was saved, but its MP4 is not ready yet. Tap Play or Share in Saved sessions to retry.\n\n${saved.recordingError}`,
          );
        }
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
  const openSession = async (session: Session, action: 'play' | 'share') => {
    if (sessionActionRef.current || busy || status.finalizing) {
      return;
    }
    const title = action === 'play' ? 'Play recording' : 'Share recording';
    if (!session.finalized) {
      Alert.alert(title, 'Stop and save the recording first.');
      return;
    }
    sessionActionRef.current = true;
    setSessionAction({ id: session.id, action });
    setBusy(true);
    try {
      const data = await Engine.exportSession(session.id);
      if (!data.finalized) {
        throw new Error('Stop and save the recording first.');
      }
      if (typeof data.folderPath !== 'string' || !data.folderPath) {
        throw new Error('The saved recording could not be found.');
      }
      if (action === 'play') {
        await Archive.previewSession(data.folderPath);
      } else {
        const recording = await Archive.archiveSession(data.folderPath);
        await Share.share({
          url: recording.url,
          title: `April Fools AR by The REFINERY — ${session.name}`,
        });
      }
    } catch (e) {
      Alert.alert(title, errorText(e));
    } finally {
      sessionActionRef.current = false;
      setSessionAction(null);
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
      const next = await Engine.setPreviewMode(mode);
      setPreview(next?.previewMode || mode);
      if (next) {
        setStatus(next);
      }
    } catch (e) {
      Alert.alert('Preview', errorText(e));
    }
  };
  const changeDebugMode = async (enabled: boolean) => {
    try {
      if (enabled) {
        await Engine.setPreviewMode('camera');
        setPreview('camera');
      }
      if (measuringTagSize) {
        await Engine.setSpatialMode('distance');
      }
      const next = await Engine.setDebugMode(enabled);
      setMeasuringTagSize(false);
      setDebugEnabled(
        typeof next?.debugMode === 'boolean' ? next.debugMode : enabled,
      );
      if (next) {
        setStatus(next);
      }
    } catch (error) {
      Alert.alert('Display mode', errorText(error));
    }
  };
  const openDebugSettings = async () => {
    try {
      if (measuringTagSize) {
        setStatus(await Engine.setSpatialMode('distance'));
      }
      setMeasuringTagSize(false);
      setDebugSettings(await Engine.getDebugSettings());
      setSettingsOpen(true);
    } catch (error) {
      Alert.alert('Debug settings', errorText(error));
    }
  };
  const openReleaseNotes = async () => {
    try {
      setAppInfo(await Engine.getAppInfo());
      setReleaseNotesOpen(true);
    } catch (error) {
      Alert.alert('Build information', errorText(error));
    }
  };
  const setViewZoom = async (zoom: number) => {
    try {
      setStatus(await Engine.setDisplayZoom(zoom));
    } catch (error) {
      Alert.alert('View zoom', errorText(error));
    }
  };
  const saveDebugSettings = async (settings: DebugSettings) => {
    setDebugSettings(await Engine.setDebugSettings(settings));
    setSettingsOpen(false);
    await refresh();
  };
  const beginTagSizeMeasurement = async () => {
    try {
      setSettingsOpen(false);
      await Engine.setSpatialMode('tagWidth');
      await Engine.setPreviewMode('camera');
      setPreview('camera');
      const next = await Engine.setDebugMode(false);
      setStatus(next);
      setDebugEnabled(false);
      setMeasuringTagSize(true);
    } catch (error) {
      Alert.alert('Measure tag width', errorText(error));
    }
  };
  const applyTagSizeMeasurement = async () => {
    try {
      setDebugSettings(await Engine.applyMeasuredTagSize());
      await changeDebugMode(true);
    } catch (error) {
      Alert.alert('Measure tag width', errorText(error));
    }
  };
  const setSpatialMode = async (
    mode: 'distance' | 'height' | 'selectFloor',
  ) => {
    try {
      setStatus(await Engine.setSpatialMode(mode));
    } catch (error) {
      Alert.alert('Measurement mode', errorText(error));
    }
  };
  const toggleFloor = async () => {
    try {
      setStatus(
        await Engine.setFloorVisible(
          !(status.spatial?.showFloorPlanes ?? true),
        ),
      );
    } catch (error) {
      Alert.alert('Floor display', errorText(error));
    }
  };
  const clearMeasurements = async () => {
    try {
      setStatus(await Engine.clearMeasurements());
    } catch (error) {
      Alert.alert('Measurements', errorText(error));
    }
  };
  const completeFloorSetup = async () => {
    const candidateId = status.spatial?.floorSetup?.candidateId;
    if (!candidateId) {
      return;
    }
    setFinishingFloor(true);
    try {
      setStatus(await Engine.completeFloorSetup(candidateId));
    } catch (error) {
      Alert.alert('Floor setup', errorText(error));
      await refresh();
    } finally {
      setFinishingFloor(false);
    }
  };
  const setStatusFromTagWidthReset = async () => {
    try {
      setStatus(await Engine.setSpatialMode('tagWidth'));
    } catch (error) {
      Alert.alert('Measure tag width', errorText(error));
    }
  };
  const m =
    measuringTagSize || status.measurement?.pointCount
      ? status.measurement
      : status.spatial?.lastMeasurement || status.measurement;
  const spatialMode = status.spatial?.mode || 'distance';
  const settingUpFloor = spatialMode === 'selectFloor';
  const floorSetup = status.spatial?.floorSetup;
  const floorSelected = status.spatial?.floorSelected ?? false;
  const floorTilt = status.spatial?.floorTiltDegrees;
  const floorTiltText =
    floorSelected || floorSetup?.candidateSelected
      ? `${settingUpFloor ? 'Detected floor tilt' : 'Floor tilt'} ${
          floorTilt != null && Number.isFinite(floorTilt)
            ? `≈${floorTilt.toFixed(1)}°`
            : 'unavailable'
        }${
          status.spatial?.levelFloorWithGravity
            ? settingUpFloor
              ? ' · level on Done'
              : ' · using level floor (0.0°)'
            : ''
        }`
      : null;
  const floorVisible = status.spatial?.showFloorPlanes ?? true;
  const measurementCount = status.spatial?.measurementCount ?? 0;
  const tags = status.aprilTag;
  const tagIDs = tags?.ids || [];
  const firstDepth = m?.points?.[0]?.depthMeters;
  const compactNameEditing = compactLandscape && editingName;
  const working = busy || status.finalizing;
  const viewZoom = Number.isFinite(status.displayZoom)
    ? status.displayZoom!
    : 1;

  const modeControls = (
    <View style={s.debugBar} testID="capture.toolbar">
      <View style={s.debugSwitch}>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Tag debug mode"
          accessibilityState={{ selected: debugEnabled }}
          onPress={() => changeDebugMode(true)}
          style={[s.debugChoice, debugEnabled && s.modeActive]}
        >
          <Text style={[s.modeText, debugEnabled && s.dark]}>Tag debug</Text>
        </Pressable>
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Measurement mode"
          accessibilityState={{ selected: !debugEnabled }}
          onPress={() => changeDebugMode(false)}
          style={[s.debugChoice, !debugEnabled && s.modeActive]}
        >
          <Text style={[s.modeText, !debugEnabled && s.dark]}>Measure</Text>
        </Pressable>
      </View>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Debug settings"
        onPress={openDebugSettings}
      >
        <Text style={s.link}>Settings</Text>
      </Pressable>
    </View>
  );
  const measurementTools = !debugEnabled ? (
    <View style={[s.measure, wide && s.measureInRail]}>
      {settingUpFloor ? (
        <>
          <Text style={s.kicker}>SET UP THE FLOOR</Text>
          <Text style={s.floorInstructions}>
            Point at the floor and move slowly to scan a larger area.
          </Text>
          <View style={[s.row, s.floorSetupRow]}>
            <View style={s.floorCoverage}>
              <Text style={s.floorCoverageValue}>
                {floorSetup?.candidateSelected &&
                floorSetup.areaSquareMeters != null &&
                Number.isFinite(floorSetup.areaSquareMeters)
                  ? `${(
                      Math.floor(floorSetup.areaSquareMeters * 100) / 100
                    ).toFixed(2)} m² scanned`
                  : 'Looking for the floor…'}
              </Text>
              <Text style={s.small}>Target: 1.00 m², at least 50 cm wide</Text>
            </View>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Finish floor setup"
              accessibilityState={{
                disabled:
                  !floorSetup?.ready ||
                  !floorSetup?.candidateId ||
                  finishingFloor,
              }}
              disabled={
                !floorSetup?.ready || !floorSetup?.candidateId || finishingFloor
              }
              onPress={completeFloorSetup}
              style={[
                s.floorDone,
                (!floorSetup?.ready ||
                  !floorSetup?.candidateId ||
                  finishingFloor) &&
                  s.dim,
              ]}
            >
              {finishingFloor ? (
                <ActivityIndicator color={C.bg} />
              ) : (
                <Text style={s.exportText}>Done</Text>
              )}
            </Pressable>
          </View>
          <Text style={s.hint}>
            {floorSetup?.ready
              ? 'Check that the highlighted surface is the floor, then tap Done.'
              : (
                  {
                    trackingLimited:
                      'Move slowly and wait for normal tracking.',
                    staleFrame: 'Waiting for a current camera frame.',
                    insufficientArea:
                      'Keep moving to extend the highlighted floor to at least 1.00 m².',
                    insufficientSpan:
                      'Scan a wider patch of floor before continuing.',
                  } as Record<string, string>
                )[floorSetup?.reason || ''] ||
                'Tap the floor if it is not selected automatically. Keep moving to extend the highlighted area.'}
          </Text>
        </>
      ) : measuringTagSize ? (
        <>
          <Text style={s.kicker}>MEASURE ONE TAG EDGE</Text>
          <Text style={s.value}>
            {m?.pointCount === 2 && m.distanceMeters != null
              ? `${(m.distanceMeters * 1000).toFixed(1)} mm`
              : `${m?.pointCount || 0} / 2 points`}
          </Text>
          <Text style={s.hint}>
            Tap adjacent black/white boundary corners on one edge. Review this
            AR/LiDAR estimate before using it.
          </Text>
          <View style={[s.row, s.measureActions]}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Cancel tag width measurement"
              onPress={() => changeDebugMode(true)}
            >
              <Text style={s.link}>Cancel</Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Reset tag width points"
              onPress={setStatusFromTagWidthReset}
            >
              <Text style={s.link}>Clear</Text>
            </Pressable>
            <Pressable
              accessibilityLabel="Use measured tag width"
              onPress={applyTagSizeMeasurement}
              disabled={m?.pointCount !== 2 || !m.distanceMeters}
              style={[
                s.export,
                (m?.pointCount !== 2 || !m.distanceMeters) && s.dim,
              ]}
            >
              <Text style={s.exportText}>Use width</Text>
            </Pressable>
          </View>
        </>
      ) : (
        <>
          <View style={s.row}>
            <View style={s.measureModeSwitch}>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Two-point measurement mode"
                accessibilityState={{
                  selected: spatialMode === 'distance',
                }}
                onPress={() => setSpatialMode('distance')}
                style={[
                  s.measureChoice,
                  spatialMode === 'distance' && s.modeActive,
                ]}
              >
                <Text
                  style={[s.modeText, spatialMode === 'distance' && s.dark]}
                >
                  Two points
                </Text>
              </Pressable>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Floor height measurement mode"
                accessibilityState={{
                  selected: spatialMode === 'height',
                }}
                onPress={() => setSpatialMode('height')}
                style={[
                  s.measureChoice,
                  spatialMode === 'height' && s.modeActive,
                ]}
              >
                <Text style={[s.modeText, spatialMode === 'height' && s.dark]}>
                  Floor height
                </Text>
              </Pressable>
            </View>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Clear all measurements"
              onPress={clearMeasurements}
              hitSlop={8}
            >
              <Text style={s.link}>Clear</Text>
            </Pressable>
          </View>
          <View style={[s.row, s.floorRow]}>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Toggle floor planes"
              accessibilityState={{ selected: floorVisible }}
              onPress={toggleFloor}
              hitSlop={6}
            >
              <Text style={s.link}>
                {floorVisible ? 'Floor on' : 'Floor off'}
              </Text>
            </Pressable>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Select floor plane"
              onPress={() => setSpatialMode('selectFloor')}
              hitSlop={6}
            >
              <Text style={s.link}>
                {floorSelected ? 'Change floor' : 'Set floor'}
              </Text>
            </Pressable>
            <Text style={s.floorState}>{`${measurementCount} measurement${
              measurementCount === 1 ? '' : 's'
            } · ${floorSelected ? 'floor set' : 'no floor'}`}</Text>
          </View>
          <View style={s.values}>
            <View style={m?.kind === 'height' && s.heightValueBlock}>
              <Text
                style={m?.kind === 'height' ? s.heightValue : s.value}
                numberOfLines={1}
                adjustsFontSizeToFit
                minimumFontScale={0.85}
              >
                {m?.kind === 'height'
                  ? formatHeight(
                      m.heightMeters ?? m.verticalMeters ?? m.distanceMeters,
                      debugSettings.showImperialHeight ?? true,
                    )
                  : m?.distanceMeters != null
                  ? `${m.distanceMeters.toFixed(3)} m`
                  : '—'}
              </Text>
              <Text style={s.small}>
                {m?.kind === 'height' ? 'Floor height' : '3D distance'}
              </Text>
            </View>
            {m?.kind !== 'height' && (
              <>
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
              </>
            )}
          </View>
          <Text style={s.hint}>
            {spatialMode === 'height'
              ? 'Tap the tag center or target surface. Height is vertical above the selected floor.'
              : m?.pointCount === 1
              ? `First point${
                  firstDepth != null
                    ? ` · ${firstDepth.toFixed(3)} m depth`
                    : ''
                }. Tap the second surface.`
              : 'Tap two surfaces. Lines stay in this AR session; record to save them.'}
          </Text>
        </>
      )}
    </View>
  ) : null;
  const recordingControls = (
    <View
      style={[
        s.controls,
        wide && s.controlsInRail,
        compactNameEditing && s.nameEditingControls,
        {
          paddingBottom: compactNameEditing ? 6 : wide ? 12 : inset.bottom + 12,
        },
      ]}
    >
      {!compactNameEditing &&
        (status.lastError ? (
          <Text numberOfLines={2} style={s.failure}>
            {status.lastError}
          </Text>
        ) : (
          <View style={[s.row, wide && s.railTelemetry]}>
            <Text style={s.telemetry}>
              {status.recording
                ? '● RECORDING'
                : status.depthAvailable
                ? 'READY TO RECORD'
                : 'WAITING FOR LIVE DEPTH'}
            </Text>
            <Text style={s.telemetry}>
              {duration(status.elapsedSeconds)} · {status.framesWritten || 0}{' '}
              frames · {status.depthFrames || 0} depth ·{' '}
              {status.droppedFrames || 0} skipped
            </Text>
          </View>
        ))}
      {!status.recording && (
        <TextInput
          accessibilityLabel="Session name"
          value={name}
          onChangeText={setName}
          onFocus={() => setEditingName(true)}
          onBlur={() => setEditingName(false)}
          onSubmitEditing={() => setEditingName(false)}
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
          style={[s.record, compactLandscape && s.recordCompact]}
          accessibilityRole="button"
          accessibilityLabel={
            status.recording ? 'Stop and save recording' : 'Start recording'
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
          accessibilityRole="button"
          accessibilityLabel="Bookmark"
          style={[
            s.bookmark,
            compactLandscape && s.bookmarkInRail,
            !status.recording && s.dim,
          ]}
        >
          <Text style={s.plus}>+</Text>
          {!compactLandscape && <Text style={s.bookmarkText}>Bookmark</Text>}
        </Pressable>
      </View>
    </View>
  );

  const sceneTools = (
    <>
      {floorTiltText && (
        <Text
          style={s.floorTilt}
          accessibilityLabel={floorTiltText}
          numberOfLines={1}
          adjustsFontSizeToFit
          minimumFontScale={0.8}
        >
          {floorTiltText}
        </Text>
      )}
      {!debugEnabled && !!status.trackingReason && (
        <Text style={s.trackingHint}>
          {status.trackingReason.replace(/([A-Z])/g, ' $1')}
        </Text>
      )}
      {!debugEnabled && !settingUpFloor && (
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
      )}
      {!debugEnabled && !settingUpFloor && (
        <View style={s.tagStatus} pointerEvents="none">
          <Text style={s.tagText} numberOfLines={1}>
            {tags?.state === 'error'
              ? tags.error || 'Detector unavailable'
              : tagIDs.length
              ? `Visible: ${tagIDs.map(id => `#${id}`).join(', ')}`
              : tags?.state === 'running' || tags?.state === 'ready'
              ? 'Looking for tags'
              : 'Waiting for camera frames'}
          </Text>
        </View>
      )}
    </>
  );

  return (
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <StatusBar barStyle="light-content" />
      <View
        style={[
          s.header,
          wide && s.headerWide,
          compactNameEditing && s.hideForKeyboard,
          {
            paddingTop: inset.top + (compactLandscape ? 4 : 9),
            paddingLeft: inset.left + 20,
            paddingRight: inset.right + 20,
          },
        ]}
      >
        <View style={[s.headerMain, wide && s.headerMainWide]}>
          <View style={[s.brandRow, wide && s.brandRowWide]}>
            <Image
              source={require('./assets/brand/app-mark.png')}
              style={[s.mark, compactLandscape && s.markCompact]}
              accessibilityLabel="The REFINERY wrench and viewfinder"
            />
            <View style={s.brandContent}>
              <Text style={[s.brand, compactLandscape && s.brandCompact]}>
                APRIL FOOLS AR
              </Text>
              <View style={s.brandMeta}>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="About and privacy"
                  onPress={() => {
                    setAboutPage('privacy');
                    setAboutOpen(true);
                  }}
                  hitSlop={8}
                  style={s.versionButton}
                >
                  <Text style={s.versionLabel}>by The REFINERY · About</Text>
                </Pressable>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Sponsors"
                  onPress={() => {
                    setAboutPage('sponsors');
                    setAboutOpen(true);
                  }}
                  hitSlop={8}
                  style={s.versionButton}
                >
                  <Text style={s.versionLabel}>Sponsors</Text>
                </Pressable>
                <Pressable
                  accessibilityRole="button"
                  accessibilityLabel="Version and release notes"
                  onPress={openReleaseNotes}
                  hitSlop={8}
                  style={s.versionButton}
                >
                  <Text style={s.versionLabel}>
                    {appInfo
                      ? `v${appInfo.version} (${
                          appInfo.build
                        }) · ${appInfo.buildCommit.slice(0, 7)}${
                          appInfo.workingTreeDirty ? '*' : ''
                        }`
                      : 'Version & release notes'}
                  </Text>
                </Pressable>
              </View>
            </View>
          </View>
          <View style={[s.tabs, wide && s.tabsWide]}>
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
        {tab === 'capture' && !wide && modeControls}
      </View>
      {tab === 'capture' ? (
        <View
          testID="capture.workspace"
          style={[
            s.workspace,
            wide && s.workspaceWide,
            wide && {
              paddingLeft: inset.left + 12,
              paddingRight: inset.right + 12,
              paddingBottom: inset.bottom + 10,
            },
          ]}
        >
          <View
            key="camera"
            testID="capture.camera"
            style={[s.camera, wide && s.cameraWide]}
          >
            {Engine ? (
              <CameraView
                testID="capture.native-camera"
                style={StyleSheet.absoluteFill}
              />
            ) : (
              <Text style={s.failure}>Native capture module unavailable.</Text>
            )}
            <View style={s.cameraTop} pointerEvents="box-none">
              <View style={s.cameraStatusBar}>
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
                  <Text
                    style={s.pillText}
                    numberOfLines={1}
                    adjustsFontSizeToFit
                    minimumFontScale={0.8}
                  >
                    {(status.tracking || 'STARTING').toUpperCase()}
                  </Text>
                </View>
                <View style={s.pill}>
                  <Text
                    style={s.pillText}
                    numberOfLines={1}
                    adjustsFontSizeToFit
                    minimumFontScale={0.8}
                  >
                    {status.depthAvailable
                      ? 'DEPTH LIVE'
                      : status.lidarAvailable
                      ? 'DEPTH WAITING'
                      : 'CHECKING LiDAR'}
                  </Text>
                </View>
                <View style={s.zoomBar}>
                  <Text style={s.zoomLabel}>{`View ${viewZoom.toFixed(
                    1,
                  )}×`}</Text>
                  {[1, 2, 4].map(zoom => (
                    <Pressable
                      key={zoom}
                      accessibilityRole="button"
                      accessibilityLabel={`View zoom ${zoom}×`}
                      accessibilityState={{
                        selected: Math.abs(viewZoom - zoom) < 0.01,
                      }}
                      onPress={() => setViewZoom(zoom)}
                      hitSlop={6}
                      style={[
                        s.zoomButton,
                        Math.abs(viewZoom - zoom) < 0.01 && s.modeActive,
                      ]}
                    >
                      <Text
                        style={[
                          s.zoomText,
                          Math.abs(viewZoom - zoom) < 0.01 && s.dark,
                        ]}
                      >
                        {zoom}×
                      </Text>
                    </Pressable>
                  ))}
                </View>
              </View>
              {!wide && sceneTools}
            </View>
            {!wide && measurementTools}
          </View>
          <View
            key="console"
            testID="capture.console"
            style={[
              s.console,
              wide && s.consoleWide,
              wide && { width: railWidth },
            ]}
          >
            {wide && (
              <View
                style={[s.toolsHeader, compactNameEditing && s.hideForKeyboard]}
              >
                {modeControls}
              </View>
            )}
            {wide && (
              <ScrollView
                style={[s.toolsScroll, compactNameEditing && s.hideForKeyboard]}
                contentContainerStyle={s.toolsContent}
                keyboardShouldPersistTaps="handled"
              >
                {sceneTools}
                {debugEnabled ? (
                  <View style={s.sceneSummary}>
                    <Text style={s.kicker}>LIVE TAGS</Text>
                    <Text style={s.sceneCount}>
                      {tagIDs.length
                        ? tagIDs.map(id => `#${id}`).join(' · ')
                        : status.tracking === 'unavailable'
                        ? 'Camera unavailable'
                        : tags?.state === 'error'
                        ? 'Detector unavailable'
                        : 'Looking for tags'}
                    </Text>
                    <Text style={s.description}>
                      Point at an AprilTag. Tap its outline to inspect distance
                      and height.
                    </Text>
                    <Text style={s.hint}>
                      {floorSelected
                        ? 'Floor selected for height estimates.'
                        : 'Set up the floor in Measure to see tag heights.'}
                    </Text>
                  </View>
                ) : (
                  measurementTools
                )}
              </ScrollView>
            )}
            {recordingControls}
          </View>
        </View>
      ) : (
        <View
          style={[
            s.sessionPage,
            {
              paddingLeft: inset.left + 20,
              paddingRight: inset.right + 20,
              paddingBottom: inset.bottom,
            },
          ]}
        >
          <View style={s.row}>
            <Text style={s.title}>Your field recordings</Text>
            <Pressable onPress={refreshSessions}>
              <Text style={s.link}>Refresh</Text>
            </Pressable>
          </View>
          <Text style={s.description}>
            Play recordings with tag and measurement overlays, or share the
            clean MP4 with its images, depth, and recorded data.
          </Text>
          <FlatList
            key={`sessions-${sessionColumns}`}
            numColumns={sessionColumns}
            columnWrapperStyle={
              sessionColumns > 1 ? s.sessionColumns : undefined
            }
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
              <View
                style={[
                  s.session,
                  sessionColumns > 1 && s.sessionTile,
                  sessionColumns > 1 && { maxWidth: sessionCardWidth },
                ]}
              >
                <Text style={s.title}>{item.name}</Text>
                <Text style={s.description}>
                  {new Date(item.createdAt).toLocaleString()}
                </Text>
                <Text style={s.description}>
                  {duration(item.durationSeconds)} ·{' '}
                  {fileSize(
                    item.recordingReady && item.recordingBytes != null
                      ? item.recordingBytes
                      : item.sizeBytes,
                  )}
                </Text>
                <View style={s.sessionActions}>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel={`Play recording ${item.name}`}
                    accessibilityState={{
                      disabled: Boolean(working || !item.finalized),
                    }}
                    disabled={Boolean(working || !item.finalized)}
                    style={[
                      s.sessionButton,
                      (working || !item.finalized) && s.dim,
                    ]}
                    onPress={() => openSession(item, 'play')}
                  >
                    <Text style={s.exportText}>Play</Text>
                  </Pressable>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel={`Share recording ${item.name}`}
                    accessibilityState={{
                      disabled: Boolean(working || !item.finalized),
                    }}
                    disabled={Boolean(working || !item.finalized)}
                    style={[
                      s.sessionButton,
                      (working || !item.finalized) && s.dim,
                    ]}
                    onPress={() => openSession(item, 'share')}
                  >
                    <Text style={s.exportText}>Share ↗</Text>
                  </Pressable>
                </View>
                {sessionAction?.id === item.id ? (
                  <View style={s.sessionProgress}>
                    <ActivityIndicator color={C.cyan} size="small" />
                    <Text
                      accessibilityRole="text"
                      accessibilityLiveRegion="polite"
                      style={s.small}
                    >
                      {sessionAction.action === 'play'
                        ? 'Opening recording…'
                        : 'Preparing to share…'}
                    </Text>
                  </View>
                ) : !item.finalized ? (
                  <Text style={s.small}>This recording is not finished.</Text>
                ) : null}
              </View>
            )}
          />
        </View>
      )}
      <ReleaseNotesModal
        visible={releaseNotesOpen}
        info={appInfo}
        onClose={() => setReleaseNotesOpen(false)}
      />
      <DebugSettingsModal
        visible={settingsOpen}
        initialSettings={debugSettings}
        onCancel={() => setSettingsOpen(false)}
        onSave={saveDebugSettings}
        onMeasure={beginTagSizeMeasurement}
      />
      <AboutModal
        visible={aboutOpen}
        initialPage={aboutPage}
        onClose={() => setAboutOpen(false)}
      />
      <Modal
        visible={noteOpen}
        supportedOrientations={[
          'portrait',
          'landscape-left',
          'landscape-right',
          'portrait-upside-down',
        ]}
        transparent
        animationType="fade"
        onRequestClose={() => setNoteOpen(false)}
      >
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : undefined}
          style={[
            s.backdrop,
            {
              paddingTop: inset.top + 12,
              paddingBottom: inset.bottom + 12,
              paddingLeft: inset.left + 16,
              paddingRight: inset.right + 16,
            },
          ]}
        >
          <ScrollView
            style={s.modal}
            contentContainerStyle={s.modalContent}
            keyboardShouldPersistTaps="handled"
          >
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
          </ScrollView>
        </KeyboardAvoidingView>
      </Modal>
    </KeyboardAvoidingView>
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
  workspace: { flex: 1, minHeight: 0 },
  workspaceWide: { flexDirection: 'row', gap: 12 },
  header: { paddingHorizontal: 20 },
  headerWide: { paddingBottom: 8 },
  headerMain: {},
  headerMainWide: { flexDirection: 'row', alignItems: 'center', gap: 20 },
  brandRowWide: { flex: 1, minWidth: 0 },
  brandCompact: { fontSize: 13, letterSpacing: 0.8 },
  markCompact: { width: 32, height: 32 },
  tabsWide: { marginTop: 0, alignSelf: 'stretch', alignItems: 'center' },
  console: { flexShrink: 0 },
  consoleWide: {
    justifyContent: 'flex-end',
    backgroundColor: C.card,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: C.line,
    overflow: 'hidden',
  },
  toolsScroll: { flex: 1, minHeight: 0 },
  hideForKeyboard: { display: 'none' },
  nameEditingControls: { paddingTop: 6 },
  toolsHeader: { paddingHorizontal: 14 },
  toolsContent: { paddingHorizontal: 14, paddingBottom: 16 },
  sceneSummary: {
    paddingVertical: 16,
    borderTopWidth: 1,
    borderTopColor: C.line,
  },
  sceneCount: { color: C.text, fontSize: 20, fontWeight: '600', marginTop: 8 },
  cameraWide: { borderRadius: 18, minWidth: 0 },
  measureInRail: {
    position: 'relative',
    bottom: 0,
    left: 0,
    right: 0,
    padding: 0,
    paddingTop: 14,
    borderWidth: 0,
    borderRadius: 0,
    backgroundColor: 'transparent',
  },
  controlsInRail: {
    paddingHorizontal: 14,
    borderTopWidth: 1,
    borderTopColor: C.line,
  },
  railTelemetry: { flexWrap: 'wrap', gap: 0 },
  recordCompact: { height: 44 },
  bookmarkInRail: { minWidth: 44 },
  sessionColumns: { gap: 14, alignItems: 'flex-start' },
  sessionTile: { flex: 1 },
  brandRow: { flexDirection: 'row', gap: 11, alignItems: 'center' },
  brandContent: { flex: 1 },
  brandMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    columnGap: 10,
  },
  versionButton: { minHeight: 28, justifyContent: 'center' },
  versionLabel: {
    color: C.cyan,
    fontSize: 10,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
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
    minHeight: 44,
    justifyContent: 'center',
    paddingBottom: 11,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  tabActive: { borderBottomColor: C.cyan },
  tabText: { color: C.muted, fontSize: 13, fontWeight: '600' },
  debugBar: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 9,
  },
  toolbarAction: {
    minHeight: 44,
    minWidth: 54,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  debugSwitch: {
    flexDirection: 'row',
    backgroundColor: C.card,
    borderRadius: 15,
    padding: 3,
  },
  debugChoice: {
    borderRadius: 12,
    minHeight: 38,
    justifyContent: 'center',
    paddingVertical: 7,
    paddingHorizontal: 13,
  },
  measureModeSwitch: { flexDirection: 'row', gap: 2 },
  measureChoice: {
    borderRadius: 12,
    paddingVertical: 7,
    paddingHorizontal: 10,
  },
  floorRow: { marginTop: 8, flexWrap: 'wrap' },
  floorTilt: {
    color: C.text,
    fontSize: 11,
    fontVariant: ['tabular-nums'],
    backgroundColor: '#071426DB',
    alignSelf: 'flex-start',
    paddingHorizontal: 9,
    paddingVertical: 4,
    marginTop: 4,
    borderRadius: 8,
  },
  floorState: {
    color: C.muted,
    fontSize: 10,
    flexShrink: 1,
    textAlign: 'right',
  },
  floorInstructions: {
    color: C.text,
    fontSize: 13,
    lineHeight: 18,
    marginTop: 7,
  },
  floorSetupRow: { marginTop: 12, flexWrap: 'wrap' },
  floorCoverage: { flex: 1, minWidth: 120 },
  floorCoverageValue: {
    color: C.cyan,
    fontSize: 16,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  floorDone: {
    minWidth: 78,
    minHeight: 44,
    borderRadius: 12,
    backgroundColor: C.cyan,
    alignItems: 'center',
    justifyContent: 'center',
  },
  cyan: { color: C.cyan },
  dark: { color: C.bg },
  camera: { flex: 1, backgroundColor: C.card, overflow: 'hidden' },
  cameraTop: { position: 'absolute', top: 14, left: 15, right: 15 },
  cameraStatusBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    height: 44,
    gap: 8,
    paddingHorizontal: 8,
    borderRadius: 22,
    backgroundColor: '#071426DB',
  },
  zoomBar: {
    flexDirection: 'row',
    alignItems: 'center',
    flexShrink: 0,
    gap: 2,
  },
  zoomLabel: {
    color: C.text,
    fontSize: 10,
    fontWeight: '600',
    marginRight: 1,
    fontVariant: ['tabular-nums'],
  },
  zoomButton: {
    minWidth: 36,
    minHeight: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  zoomText: { color: C.text, fontSize: 12, fontWeight: '600' },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 10,
  },
  pill: {
    flexDirection: 'row',
    flexShrink: 1,
    minWidth: 0,
    gap: 4,
    alignItems: 'center',
  },
  pillText: {
    fontSize: 9,
    flexShrink: 1,
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
  tagStatus: {
    backgroundColor: '#071426E8',
    borderRadius: 12,
    paddingHorizontal: 12,
    paddingVertical: 6,
    marginTop: 12,
    alignSelf: 'flex-start',
    maxWidth: '100%',
  },
  tagText: { color: C.cyan, fontSize: 12, fontWeight: '600' },
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
    flexWrap: 'wrap',
    gap: 16,
    alignItems: 'center',
    marginTop: 10,
  },
  value: {
    color: C.text,
    fontSize: 24,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  heightValueBlock: { flex: 1 },
  heightValue: {
    color: C.text,
    fontSize: 20,
    fontWeight: '600',
    fontVariant: ['tabular-nums'],
  },
  small: { color: C.muted, fontSize: 10, marginTop: 4 },
  divider: { width: 1, height: 33, backgroundColor: C.line },
  hint: { fontSize: 10, color: C.muted, marginTop: 12 },
  measureActions: { marginTop: 12 },
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
  sessionPage: {
    flex: 1,
    width: '100%',
    maxWidth: 1440,
    alignSelf: 'center',
    paddingHorizontal: 20,
    paddingTop: 20,
  },
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
  sessionActions: { flexDirection: 'row', gap: 10, marginTop: 8 },
  sessionButton: {
    backgroundColor: C.cyan,
    minHeight: 44,
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 13,
    borderRadius: 9,
  },
  sessionProgress: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginTop: 6,
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
  modal: {
    flexGrow: 0,
    width: '100%',
    maxWidth: 560,
    maxHeight: '100%',
    alignSelf: 'center',
    backgroundColor: C.card,
    borderRadius: 21,
  },
  modalContent: { padding: 22, gap: 14 },
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
