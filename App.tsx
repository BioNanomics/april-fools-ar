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
import { AppVersionBadge } from './AppVersionBadge';
import {
  FieldDefinitionsPanel,
  type FieldTag,
  type FieldStatus,
} from './FieldDefinitionsPanel';

const CameraView = requireNativeComponent<ViewProps>('ARCaptureView');
const TagReadoutView = requireNativeComponent<ViewProps>(
  'ARCaptureReadoutView',
);
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
  field?: FieldStatus;
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
  const landscape = width > height;
  const sideWidth = Math.min(380, usableWidth * 0.44);
  const sideTop = inset.top + 60;
  const sideBottom = inset.bottom + 8;
  const sideHeight = Math.max(0, height - sideTop - sideBottom);
  const denseDock = height < 360;
  const listWidth = landscape ? sideWidth : Math.min(760, usableWidth);
  const sessionColumns = listWidth >= 680 ? 2 : 1;
  const sessionCardWidth =
    (listWidth - 32 - 14 * (sessionColumns - 1)) / sessionColumns;
  const [toolSheet, setToolSheet] = useState<
    'more' | 'measure' | 'name' | 'details' | null
  >(null);
  const [tab, setTab] = useState<'capture' | 'sessions'>('capture');
  const [status, setStatus] = useState<Status>({});
  const [name, setName] = useState('Field walk');
  const [busy, setBusy] = useState(false);
  const [sessionAction, setSessionAction] = useState<{
    id: string;
    action: 'play' | 'share' | 'delete';
  } | null>(null);
  const sessionActionRef = useRef(false);
  const [sessions, setSessions] = useState<Session[]>([]);
  const sessionsRefreshRef = useRef(0);
  const [noteOpen, setNoteOpen] = useState(false);
  const [note, setNote] = useState('');
  const [preview, setPreview] = useState('camera');
  const [appInfo, setAppInfo] = useState<AppInfo | null>(null);
  const [releaseNotesOpen, setReleaseNotesOpen] = useState(false);
  const [aboutOpen, setAboutOpen] = useState(false);
  const [aboutPage, setAboutPage] = useState<AboutPage>('about');
  const pendingVersionRef = useRef(false);
  const versionClosingRef = useRef(false);
  const releaseNotesOpenRef = useRef(false);
  releaseNotesOpenRef.current = releaseNotesOpen;
  const [debugEnabled, setDebugEnabled] = useState(true);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [fieldsOpen, setFieldsOpen] = useState(false);
  const [fieldSession, setFieldSession] = useState<Session | null>(null);
  const fieldEvidenceRef = useRef<{
    session: Session;
    seconds: number;
  } | null>(null);
  const [measuringTagSize, setMeasuringTagSize] = useState(false);
  const [finishingFloor, setFinishingFloor] = useState(false);
  const [togglingKalman, setTogglingKalman] = useState(false);
  const togglingKalmanRef = useRef(false);
  const [debugSettings, setDebugSettings] = useState<DebugSettings>(
    DEFAULT_DEBUG_SETTINGS,
  );
  const recordingRef = useRef(false);
  recordingRef.current = Boolean(status.recording);
  const tagSelectionAllowedRef = useRef(true);
  tagSelectionAllowedRef.current =
    tab === 'capture' &&
    !settingsOpen &&
    !aboutOpen &&
    !releaseNotesOpen &&
    !noteOpen &&
    !fieldsOpen;
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
    if (sessionActionRef.current) {
      return;
    }
    const request = ++sessionsRefreshRef.current;
    try {
      const next = await Engine.listSessions();
      if (request === sessionsRefreshRef.current) {
        setSessions(next);
      }
    } catch (e) {
      Alert.alert('Sessions', errorText(e));
    }
  }, []);
  useEffect(() => {
    const subscription = Engine
      ? new NativeEventEmitter(Engine).addListener('ARCaptureStatus', setStatus)
      : undefined;
    const tagSelection = Engine
      ? new NativeEventEmitter(Engine).addListener(
          'ARCaptureTagSelected',
          (event: { id?: unknown } | undefined) => {
            if (
              !tagSelectionAllowedRef.current ||
              pendingVersionRef.current ||
              versionClosingRef.current ||
              typeof event?.id !== 'number' ||
              !Number.isSafeInteger(event.id) ||
              event.id < 0
            ) {
              return;
            }
            setToolSheet('details');
          },
        )
      : undefined;
    refresh();
    const interval = setInterval(refresh, 2000);
    return () => {
      subscription?.remove();
      tagSelection?.remove();
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
  const reportedImperialHeight =
    status.aprilTag?.debugSettings?.showImperialHeight;
  const reportedKalmanEnabled =
    status.aprilTag?.debugSettings?.kalmanFilterEnabled;
  const reportedKalmanSamples =
    status.aprilTag?.debugSettings?.kalmanFilterSamples;
  useEffect(() => {
    setDebugSettings(previous => {
      const showImperialHeight =
        typeof reportedImperialHeight === 'boolean'
          ? reportedImperialHeight
          : previous.showImperialHeight;
      const kalmanFilterEnabled =
        typeof reportedKalmanEnabled === 'boolean'
          ? reportedKalmanEnabled
          : previous.kalmanFilterEnabled;
      const kalmanFilterSamples =
        reportedKalmanSamples ?? previous.kalmanFilterSamples;
      if (
        previous.showImperialHeight === showImperialHeight &&
        previous.kalmanFilterEnabled === kalmanFilterEnabled &&
        previous.kalmanFilterSamples === kalmanFilterSamples
      ) {
        return previous;
      }
      return {
        ...previous,
        showImperialHeight,
        kalmanFilterEnabled,
        kalmanFilterSamples,
      };
    });
  }, [reportedImperialHeight, reportedKalmanEnabled, reportedKalmanSamples]);
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
  const openSession = async (
    session: Session,
    action: 'play' | 'share',
    startSeconds?: number,
  ) => {
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
        if (startSeconds != null) {
          if (
            !Number.isFinite(startSeconds) ||
            startSeconds < 0 ||
            typeof Archive.previewSessionAtTime !== 'function'
          ) {
            throw new Error('Recorded-time video navigation is unavailable.');
          }
          await Archive.previewSessionAtTime(data.folderPath, startSeconds);
        } else {
          await Archive.previewSession(data.folderPath);
        }
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
  const deleteSession = (session: Session) => {
    if (
      sessionActionRef.current ||
      busy ||
      status.finalizing ||
      (status.recording && status.sessionId === session.id)
    ) {
      return;
    }
    sessionActionRef.current = true;
    setBusy(true);
    let confirmed = false;
    const finish = () => {
      sessionActionRef.current = false;
      setSessionAction(null);
      setBusy(false);
    };
    const remove = async () => {
      if (confirmed || !sessionActionRef.current) {
        return;
      }
      confirmed = true;
      setSessionAction({ id: session.id, action: 'delete' });
      try {
        await Engine.deleteSession(session.id);
        // Ignore a list request that started before this deletion completed.
        sessionsRefreshRef.current++;
        setSessions(previous =>
          previous.filter(item => item.id !== session.id),
        );
      } catch (e) {
        Alert.alert('Delete recording', errorText(e));
      } finally {
        finish();
      }
    };
    Alert.alert(
      'Delete recording?',
      `Permanently delete “${session.name}” from this device? Its video and original capture data will be removed. This cannot be undone.`,
      [
        { text: 'Cancel', style: 'cancel', onPress: finish },
        { text: 'Delete', style: 'destructive', onPress: remove },
      ],
      {
        cancelable: true,
        onDismiss: () => {
          if (!confirmed) {
            finish();
          }
        },
      },
    );
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
      setToolSheet(null);
      setSettingsOpen(true);
    } catch (error) {
      Alert.alert('Debug settings', errorText(error));
    }
  };
  const openReleaseNotes = async () => {
    if (
      releaseNotesOpenRef.current ||
      pendingVersionRef.current ||
      versionClosingRef.current
    ) {
      return;
    }
    setToolSheet(null);
    if (settingsOpen || aboutOpen || noteOpen) {
      // UIKit must finish dismissing the current modal before presenting the full screen.
      pendingVersionRef.current = true;
      setSettingsOpen(false);
      setAboutOpen(false);
      setNoteOpen(false);
    } else {
      releaseNotesOpenRef.current = true;
      setReleaseNotesOpen(true);
    }
    try {
      setAppInfo(await Engine.getAppInfo());
    } catch (error) {
      Alert.alert('Build information', errorText(error));
    }
  };
  const finishModalDismissal = () => {
    if (!pendingVersionRef.current) {
      return;
    }
    pendingVersionRef.current = false;
    releaseNotesOpenRef.current = true;
    setReleaseNotesOpen(true);
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
  const toggleKalmanFilter = async () => {
    if (!Engine || togglingKalmanRef.current) {
      return;
    }
    togglingKalmanRef.current = true;
    setTogglingKalman(true);
    try {
      const settings = await Engine.setDebugSettings({
        kalmanFilterEnabled: !(debugSettings.kalmanFilterEnabled ?? false),
      });
      setDebugSettings(previous => ({ ...previous, ...settings }));
    } catch (error) {
      Alert.alert('Kalman filter', errorText(error));
    } finally {
      togglingKalmanRef.current = false;
      setTogglingKalman(false);
    }
  };
  const beginTagSizeMeasurement = async () => {
    try {
      setSettingsOpen(false);
      setTab('capture');
      setToolSheet('measure');
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
  const working = busy || status.finalizing;
  const viewZoom = Number.isFinite(status.displayZoom)
    ? status.displayZoom!
    : 1;

  const closeTools = () => {
    Keyboard.dismiss();
    setToolSheet(null);
  };
  const openFields = () => {
    closeTools();
    setFieldSession(null);
    setFieldsOpen(true);
  };
  const navigation = (
    <View
      style={[s.dockRow, landscape && s.sideNavigation]}
      testID="capture.navigation"
    >
      <Pressable
        accessibilityRole="tab"
        accessibilityLabel="Tag debug mode"
        accessibilityState={{ selected: tab === 'capture' && debugEnabled }}
        onPress={() => {
          setTab('capture');
          setToolSheet(null);
          changeDebugMode(true);
        }}
        style={[
          s.dockTab,
          landscape && s.sideNavButton,
          tab === 'capture' && debugEnabled && s.modeActive,
        ]}
      >
        <Text style={[s.modeText, tab === 'capture' && debugEnabled && s.dark]}>
          Tags
        </Text>
      </Pressable>
      <Pressable
        accessibilityRole="tab"
        accessibilityLabel="Measurement mode"
        accessibilityState={{ selected: tab === 'capture' && !debugEnabled }}
        onPress={() => {
          setTab('capture');
          setToolSheet('measure');
          changeDebugMode(false);
        }}
        style={[
          s.dockTab,
          landscape && s.sideNavButton,
          tab === 'capture' && !debugEnabled && s.modeActive,
        ]}
      >
        <Text
          style={[s.modeText, tab === 'capture' && !debugEnabled && s.dark]}
        >
          Measure
        </Text>
      </Pressable>
      <Pressable
        accessibilityRole="tab"
        accessibilityLabel="Saved sessions"
        accessibilityState={{
          selected: tab === 'sessions',
          disabled: Boolean(status.recording || working),
        }}
        disabled={Boolean(status.recording || working)}
        onPress={() => {
          setToolSheet(null);
          setTab('sessions');
          refreshSessions();
        }}
        style={[
          s.dockTab,
          landscape && s.sideNavButton,
          tab === 'sessions' && s.modeActive,
          (status.recording || working) && s.dim,
        ]}
      >
        <Text style={[s.modeText, tab === 'sessions' && s.dark]}>Saved</Text>
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Field definitions and tags seen"
        onPress={openFields}
        style={[s.dockIcon, landscape && s.sideNavButton]}
      >
        <Text style={s.link}>Fields</Text>
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Tag details"
        onPress={() => {
          setTab('capture');
          setToolSheet('details');
        }}
        style={[s.dockIcon, landscape && s.sideNavButton]}
      >
        <Text style={s.link}>Details</Text>
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="More controls"
        accessibilityState={{ expanded: toolSheet === 'more' }}
        onPress={() => setToolSheet(toolSheet === 'more' ? null : 'more')}
        style={[s.dockIcon, landscape && s.sideNavButton]}
      >
        <Text style={s.link}>More</Text>
      </Pressable>
    </View>
  );
  const zoomControls = (
    <View style={[s.zoomBar, landscape && s.sideZoomBar]}>
      {[1, 2, 4].map(zoom => (
        <Pressable
          key={zoom}
          accessibilityRole="button"
          accessibilityLabel={`View zoom ${zoom}×`}
          accessibilityState={{ selected: Math.abs(viewZoom - zoom) < 0.01 }}
          onPress={() => setViewZoom(zoom)}
          style={[
            s.zoomButton,
            landscape && s.sideZoomButton,
            Math.abs(viewZoom - zoom) < 0.01 && s.modeActive,
          ]}
        >
          <Text
            style={[s.zoomText, Math.abs(viewZoom - zoom) < 0.01 && s.dark]}
          >
            {zoom}×
          </Text>
        </Pressable>
      ))}
    </View>
  );
  const settingsButton = (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel="Debug settings"
      onPress={openDebugSettings}
      style={s.dockIcon}
    >
      <Text style={s.link}>Settings</Text>
    </Pressable>
  );
  const quickControls = (
    <View
      style={[s.dockRow, landscape && s.sideQuickControls]}
      testID="capture.quickControls"
    >
      <Pressable
        testID="capture.filterToggle"
        accessibilityRole="checkbox"
        accessibilityLabel="Kalman filter"
        accessibilityHint="Switch smoothing on or off. Change the sample count in Settings."
        accessibilityValue={{
          text: `${debugSettings.kalmanFilterSamples ?? 5} samples`,
        }}
        accessibilityState={{
          checked: debugSettings.kalmanFilterEnabled ?? false,
          disabled: togglingKalman || !Engine,
          busy: togglingKalman,
        }}
        disabled={togglingKalman || !Engine}
        onPress={toggleKalmanFilter}
        style={[
          s.quickFilter,
          landscape && s.sideFilter,
          debugSettings.kalmanFilterEnabled && s.quickFilterActive,
          togglingKalman && s.quickFilterPending,
        ]}
      >
        <View
          style={[
            s.quickFilterCheckbox,
            debugSettings.kalmanFilterEnabled && s.quickFilterCheckboxActive,
          ]}
        >
          {debugSettings.kalmanFilterEnabled && (
            <Text style={s.quickFilterCheckmark}>✓</Text>
          )}
        </View>
        <Text style={s.quickFilterText}>
          Kalman {debugSettings.kalmanFilterEnabled ? 'on' : 'off'}
        </Text>
      </Pressable>
      {landscape && settingsButton}
      {zoomControls}
      {!landscape && settingsButton}
    </View>
  );
  const measurementTools = !debugEnabled ? (
    <View style={s.measure}>
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
      style={[s.recordRow, landscape && s.sideRecordRow]}
      testID="capture.recordingControls"
    >
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Edit session name"
        accessibilityValue={{ text: name }}
        disabled={Boolean(status.recording || working)}
        onPress={() => setToolSheet('name')}
        style={[
          s.nameButton,
          landscape && s.sideNameButton,
          (status.recording || working) && s.dim,
        ]}
      >
        <Text style={s.small} numberOfLines={1}>
          Name
        </Text>
        <Text style={s.link} numberOfLines={1}>
          {name}
        </Text>
      </Pressable>
      <Pressable
        onPress={toggle}
        disabled={working || !Engine}
        style={[s.record, landscape && s.sideRecord]}
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
            <Text style={[s.recordText, landscape && s.sideRecordText]}>
              {status.recording
                ? landscape
                  ? 'Stop'
                  : 'Stop & save'
                : 'Record'}
            </Text>
          </>
        )}
      </Pressable>
      <Pressable
        onPress={() => setNoteOpen(true)}
        disabled={!status.recording || working}
        accessibilityRole="button"
        accessibilityLabel="Bookmark"
        style={[s.bookmark, !status.recording && s.dim]}
      >
        <Text style={s.plus}>+</Text>
        <Text style={s.bookmarkText}>Mark</Text>
      </Pressable>
    </View>
  );
  const previewControls =
    !debugEnabled && !settingUpFloor ? (
      <View style={s.modes}>
        {['camera', 'depth', 'confidence'].map(mode => (
          <Pressable
            key={mode}
            accessibilityRole="button"
            accessibilityLabel={`${mode} preview`}
            accessibilityState={{ selected: preview === mode }}
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
    ) : null;
  const moreActions = (
    <View style={s.moreActions}>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="About and sponsors"
        style={s.menuAction}
        onPress={() => {
          closeTools();
          setAboutPage('about');
          setAboutOpen(true);
        }}
      >
        <Text style={s.link}>About & sponsors · The REFINERY</Text>
      </Pressable>
      <Pressable
        accessibilityRole="button"
        accessibilityLabel="Version and release notes"
        onPress={openReleaseNotes}
        style={s.menuAction}
      >
        <Text style={s.link}>
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
  );
  const fieldStatusReason =
    status.field?.reason || status.field?.warnings?.at(-1) || '';
  const fieldStatus = status.field?.packageId ? (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={`Field alignment: ${
        status.field.alignment || 'unaligned'
      }. ${fieldStatusReason || status.field.label || ''}`}
      onPress={openFields}
      style={s.fieldStatus}
    >
      <Text style={s.fieldStatusTitle} numberOfLines={1}>
        {status.field.label} · {status.field.alignment || 'unaligned'}
      </Text>
      {!!fieldStatusReason && (
        <Text
          style={s.fieldStatusReason}
          numberOfLines={3}
          accessibilityLiveRegion="polite"
        >
          {fieldStatusReason}
        </Text>
      )}
    </Pressable>
  ) : null;
  return (
    <KeyboardAvoidingView
      style={s.root}
      behavior={Platform.OS === 'ios' ? 'padding' : undefined}
    >
      <StatusBar barStyle="light-content" />
      {tab === 'capture' ? (
        <View testID="capture.workspace" style={s.workspace}>
          <View key="camera" testID="capture.camera" style={s.camera}>
            {Engine ? (
              <CameraView
                testID="capture.native-camera"
                style={StyleSheet.absoluteFill}
              />
            ) : (
              <Text style={s.failure}>Native capture module unavailable.</Text>
            )}
            <View
              style={[
                s.cameraTop,
                {
                  top: inset.top + 8,
                  left: inset.left + 15,
                  right: inset.right + (landscape ? sideWidth + 24 : 15),
                },
              ]}
              pointerEvents="none"
            >
              <View style={[s.brandRow, !landscape && s.brandWithVersion]}>
                <Image
                  source={require('./assets/brand/app-mark.png')}
                  style={s.mark}
                  accessibilityLabel="The REFINERY wrench and viewfinder"
                />
                <Text
                  style={s.brand}
                  numberOfLines={1}
                  adjustsFontSizeToFit
                  minimumFontScale={0.8}
                >
                  APRIL FOOLS AR
                </Text>
              </View>
              <View style={s.passiveStatus}>
                <Text style={s.pillText}>
                  {(status.tracking || 'STARTING').toUpperCase()} ·{' '}
                  {status.depthAvailable
                    ? 'DEPTH LIVE'
                    : status.lidarAvailable
                    ? 'DEPTH WAITING'
                    : 'CHECKING LiDAR'}
                </Text>
                <Text style={s.pillText}>{`View ${viewZoom.toFixed(1)}×`}</Text>
              </View>
              {floorTiltText && (
                <Text style={s.floorTilt} accessibilityLabel={floorTiltText}>
                  {floorTiltText}
                </Text>
              )}
              {!debugEnabled && (
                <Text style={s.tagText} numberOfLines={1}>
                  {tags?.state === 'error'
                    ? tags.error || 'Detector unavailable'
                    : tagIDs.length
                    ? `Visible: ${tagIDs.map(id => `#${id}`).join(', ')}`
                    : 'Looking for tags'}
                </Text>
              )}
              {status.lastError ? (
                <Text style={s.failure}>{status.lastError}</Text>
              ) : (
                <Text style={s.telemetry}>
                  {status.recording ? '● RECORDING' : 'READY'} ·{' '}
                  {duration(status.elapsedSeconds)} ·{' '}
                  {status.framesWritten || 0} frames
                </Text>
              )}
            </View>
          </View>
        </View>
      ) : (
        <View
          style={[
            s.savedBackdrop,
            { paddingTop: inset.top + 24 },
            landscape && { marginRight: sideWidth + inset.right + 16 },
          ]}
          pointerEvents="none"
        >
          <Image
            source={require('./assets/brand/app-mark.png')}
            style={s.mark}
          />
          <Text style={s.title}>Your field recordings</Text>
          <Text style={s.description}>
            Browse, play, share and delete from the controls{' '}
            {landscape ? 'on the right' : 'below'}.
          </Text>
        </View>
      )}
      <View
        testID="capture.thumbDock"
        style={[
          s.thumbDock,
          {
            maxHeight: height / 2,
            height: toolSheet || tab === 'sessions' ? height / 2 : undefined,
            paddingLeft: inset.left + 10,
            paddingRight: inset.right + 10,
            paddingBottom: inset.bottom + (denseDock ? 0 : 4),
          },
          denseDock && s.denseDock,
          landscape && s.sideDock,
          landscape && {
            width: sideWidth,
            top: sideTop,
            right: inset.right + 8,
            bottom: sideBottom,
            height: sideHeight,
            maxHeight: sideHeight,
            paddingLeft: 10,
            paddingRight: 10,
            paddingBottom: 8,
          },
        ]}
      >
        {toolSheet ? (
          <View testID="capture.toolSheet" style={s.toolSheet}>
            <View style={s.toolSheetHeader}>
              <Text style={s.sheetTitle}>
                {toolSheet === 'more'
                  ? 'More controls'
                  : toolSheet === 'name'
                  ? 'Session name'
                  : toolSheet === 'details'
                  ? 'Tag details'
                  : settingUpFloor
                  ? 'Floor setup'
                  : 'Measure'}
              </Text>
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Close capture tools"
                onPress={closeTools}
                style={s.dockIcon}
              >
                <Text style={s.link}>Done</Text>
              </Pressable>
            </View>
            <ScrollView
              style={s.toolScroll}
              contentContainerStyle={s.toolContent}
              keyboardShouldPersistTaps="handled"
            >
              {toolSheet === 'more' ? (
                moreActions
              ) : toolSheet === 'name' ? (
                <>
                  <TextInput
                    accessibilityLabel="Session name"
                    value={name}
                    onChangeText={setName}
                    onSubmitEditing={closeTools}
                    style={s.input}
                    placeholder="Session name"
                    placeholderTextColor={C.muted}
                    returnKeyType="done"
                  />
                  <Text style={s.description}>
                    Name the next field recording.
                  </Text>
                </>
              ) : toolSheet === 'details' ? (
                <TagReadoutView
                  testID="capture.tagReadout"
                  style={s.tagReadout}
                />
              ) : (
                <>
                  {previewControls}
                  {measurementTools}
                </>
              )}
            </ScrollView>
          </View>
        ) : (
          <>
            {landscape && tab === 'capture' ? (
              <ScrollView
                style={s.toolScroll}
                contentContainerStyle={s.sideControls}
                keyboardShouldPersistTaps="handled"
              >
                {fieldStatus}
                {navigation}
                {quickControls}
              </ScrollView>
            ) : (
              <>
                {tab === 'capture' && fieldStatus}
                {navigation}
                {tab === 'capture' && quickControls}
              </>
            )}
            {tab === 'sessions' && (
              <View style={s.savedTools}>
                <View style={s.toolSheetHeader}>
                  <Text style={s.sheetTitle}>Saved sessions</Text>
                  <Pressable
                    accessibilityRole="button"
                    accessibilityLabel="Refresh saved sessions"
                    onPress={refreshSessions}
                    accessibilityState={{ disabled: Boolean(working) }}
                    disabled={Boolean(working)}
                    style={[s.dockIcon, working && s.dim]}
                  >
                    <Text style={s.link}>Refresh</Text>
                  </Pressable>
                </View>
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
                          accessibilityLabel={`Field walk for ${item.name}`}
                          disabled={Boolean(working || !item.finalized)}
                          accessibilityState={{
                            disabled: Boolean(working || !item.finalized),
                          }}
                          style={[
                            s.sessionButton,
                            (working || !item.finalized) && s.dim,
                          ]}
                          onPress={() => {
                            setFieldSession(item);
                            setFieldsOpen(true);
                          }}
                        >
                          <Text style={s.exportText}>Tags seen</Text>
                        </Pressable>
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
                        <Pressable
                          accessibilityRole="button"
                          accessibilityLabel={`Delete recording ${item.name}`}
                          accessibilityHint="Permanently removes the video and original capture data."
                          accessibilityState={{
                            disabled: Boolean(
                              working ||
                                (status.recording &&
                                  status.sessionId === item.id),
                            ),
                          }}
                          disabled={Boolean(
                            working ||
                              (status.recording &&
                                status.sessionId === item.id),
                          )}
                          style={[
                            s.sessionButton,
                            s.deleteButton,
                            (working ||
                              (status.recording &&
                                status.sessionId === item.id)) &&
                              s.dim,
                          ]}
                          onPress={() => deleteSession(item)}
                        >
                          <Text style={s.exportText}>Delete</Text>
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
                              : sessionAction.action === 'share'
                              ? 'Preparing to share…'
                              : 'Deleting recording…'}
                          </Text>
                        </View>
                      ) : !item.finalized ? (
                        <Text style={s.small}>
                          This recording is not finished.
                        </Text>
                      ) : null}
                    </View>
                  )}
                />
              </View>
            )}
          </>
        )}
        {tab === 'capture' && recordingControls}
      </View>
      <AppVersionBadge info={appInfo} onPress={openReleaseNotes} />
      <FieldDefinitionsPanel
        visible={fieldsOpen}
        engine={Engine}
        recording={Boolean(status.recording || status.finalizing)}
        field={status.field}
        savedSession={fieldSession}
        onClose={() => {
          setFieldsOpen(false);
          setFieldSession(null);
        }}
        onDismiss={async () => {
          const evidence = fieldEvidenceRef.current;
          fieldEvidenceRef.current = null;
          if (evidence) {
            await openSession(evidence.session, 'play', evidence.seconds);
          }
        }}
        onOpenEvidence={(tag: FieldTag) => {
          if (
            !fieldSession ||
            !Number.isFinite(tag.videoTimeSeconds) ||
            tag.videoTimeSeconds == null ||
            tag.videoTimeSeconds < 0
          ) {
            return;
          }
          fieldEvidenceRef.current = {
            session: fieldSession,
            seconds: tag.videoTimeSeconds,
          };
          setFieldsOpen(false);
          setFieldSession(null);
        }}
        onChange={field => setStatus(previous => ({ ...previous, field }))}
        onSetFloor={async () => {
          setFieldsOpen(false);
          setFieldSession(null);
          setTab('capture');
          setToolSheet('measure');
          await setSpatialMode('selectFloor');
          await changeDebugMode(false);
        }}
      />
      <ReleaseNotesModal
        visible={releaseNotesOpen}
        info={appInfo}
        onClose={() => {
          versionClosingRef.current = true;
          releaseNotesOpenRef.current = false;
          setReleaseNotesOpen(false);
        }}
        onDismiss={() => {
          versionClosingRef.current = false;
        }}
      />
      <DebugSettingsModal
        appVersion={appInfo}
        onOpenVersion={openReleaseNotes}
        onDismiss={finishModalDismissal}
        visible={settingsOpen}
        initialSettings={debugSettings}
        onCancel={() => setSettingsOpen(false)}
        onSave={saveDebugSettings}
        onMeasure={beginTagSizeMeasurement}
      />
      <AboutModal
        appVersion={appInfo}
        onOpenVersion={openReleaseNotes}
        onDismiss={finishModalDismissal}
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
        onDismiss={finishModalDismissal}
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
            landscape && { paddingTop: sideTop, alignItems: 'flex-end' },
          ]}
        >
          <ScrollView
            style={[
              s.modal,
              { maxHeight: height / 2 - inset.bottom - 12 },
              landscape && {
                width: sideWidth,
                maxHeight: sideHeight,
                alignSelf: 'flex-end',
              },
            ]}
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
        <AppVersionBadge info={appInfo} onPress={openReleaseNotes} />
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
  fieldStatus: {
    borderRadius: 8,
    padding: 8,
    backgroundColor: '#071426DD',
    marginBottom: 6,
  },
  fieldStatusTitle: { color: C.cyan, fontSize: 12, fontWeight: '600' },
  fieldStatusReason: {
    color: '#FFCB7A',
    fontSize: 12,
    lineHeight: 16,
    marginTop: 3,
  },
  root: { flex: 1, backgroundColor: C.bg },
  thumbDock: {
    position: 'absolute',
    bottom: 0,
    alignSelf: 'center',
    width: '100%',
    maxWidth: 760,
    paddingTop: 4,
    gap: 4,
    backgroundColor: '#071426F5',
    borderTopWidth: 1,
    borderTopColor: C.line,
    borderTopLeftRadius: 18,
    borderTopRightRadius: 18,
  },
  denseDock: { paddingTop: 0, gap: 0 },
  sideDock: {
    alignSelf: 'auto',
    borderWidth: 1,
    borderColor: C.line,
    borderRadius: 18,
    paddingTop: 8,
    gap: 8,
  },
  sideControls: { gap: 8, paddingBottom: 8 },
  sideNavigation: { flexWrap: 'wrap', justifyContent: 'flex-start' },
  sideNavButton: { flex: 0, width: '32%', minWidth: 44 },
  sideQuickControls: { flexWrap: 'wrap' },
  sideFilter: { flexGrow: 1 },
  sideZoomBar: { width: '100%' },
  sideZoomButton: { flex: 1, minWidth: 44 },
  sideRecordRow: { gap: 6, flexShrink: 0 },
  sideNameButton: { width: 60 },
  sideRecord: { gap: 6 },
  sideRecordText: { fontSize: 13 },
  dockRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    gap: 4,
    minHeight: 44,
  },
  dockTab: {
    flex: 1,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    borderRadius: 10,
  },
  dockIcon: {
    minWidth: 48,
    minHeight: 44,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  nameButton: {
    width: 76,
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 6,
  },
  toolSheet: { flex: 1, minHeight: 0 },
  toolSheetHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    minHeight: 44,
  },
  sheetTitle: { color: C.text, fontSize: 14, fontWeight: '700' },
  toolScroll: { flex: 1, minHeight: 0 },
  toolContent: { paddingBottom: 8 },
  moreActions: { gap: 2 },
  menuAction: { minHeight: 44, paddingHorizontal: 8, justifyContent: 'center' },
  tagReadout: { height: 350, width: '100%' },
  passiveStatus: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
    paddingVertical: 7,
  },
  savedBackdrop: {
    flex: 1,
    alignItems: 'center',
    paddingHorizontal: 24,
    gap: 8,
  },
  savedTools: { flex: 1, minHeight: 0 },
  workspace: { flex: 1, minHeight: 0 },

  sessionColumns: { gap: 14, alignItems: 'flex-start' },
  sessionTile: { flex: 1 },
  brandRow: { flexDirection: 'row', gap: 11, alignItems: 'center' },
  brandWithVersion: { paddingRight: 110 },

  mark: {
    width: 39,
    height: 44,
    borderWidth: 1.5,
    borderColor: C.cyan,
    borderRadius: 11,
    alignItems: 'center',
    justifyContent: 'center',
  },

  brand: {
    color: C.text,
    fontSize: 14,
    fontWeight: '800',
    letterSpacing: 1.4,
    flexShrink: 1,
  },
  kicker: {
    color: C.muted,
    fontSize: 9,
    fontWeight: '700',
    letterSpacing: 1.2,
    marginTop: 4,
  },

  quickFilter: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    minHeight: 44,
    paddingHorizontal: 8,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: C.line,
    backgroundColor: C.card,
  },
  quickFilterActive: { borderColor: C.cyan },
  quickFilterPending: { opacity: 0.6 },

  quickFilterCheckbox: {
    width: 22,
    height: 22,
    borderWidth: 1,
    borderColor: C.cyan,
    borderRadius: 4,
    alignItems: 'center',
    justifyContent: 'center',
  },
  quickFilterCheckboxActive: { backgroundColor: C.cyan },
  quickFilterCheckmark: { color: C.bg, fontSize: 16, fontWeight: '700' },
  quickFilterText: { color: C.text, fontSize: 13, fontWeight: '600' },

  measureModeSwitch: { flexDirection: 'row', gap: 2 },
  measureChoice: {
    minHeight: 44,
    justifyContent: 'center',
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

  dark: { color: C.bg },
  camera: { flex: 1, backgroundColor: C.card, overflow: 'hidden' },
  cameraTop: { position: 'absolute', top: 14, left: 15, right: 15 },

  zoomBar: {
    flexDirection: 'row',
    alignItems: 'center',
    flexShrink: 0,
    gap: 2,
  },

  zoomButton: {
    minWidth: 44,
    minHeight: 44,
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

  pillText: {
    fontSize: 9,
    flexShrink: 1,
    color: C.text,
    fontWeight: '700',
    letterSpacing: 0.6,
  },

  modes: {
    flexDirection: 'row',
    padding: 3,
    backgroundColor: '#071426DD',
    borderRadius: 20,
    alignSelf: 'center',
    marginTop: 12,
  },
  mode: {
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 14,
    borderRadius: 17,
  },
  modeActive: { backgroundColor: C.cyan },
  modeText: { fontSize: 11, fontWeight: '600', color: C.text },

  tagText: { color: C.cyan, fontSize: 12, fontWeight: '600' },
  measure: {
    position: 'relative',
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

  telemetry: {
    fontSize: 9,
    color: C.muted,
    fontVariant: ['tabular-nums'],
    marginBottom: 11,
  },
  input: {
    height: 44,
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
    height: 44,
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
    minWidth: 48,
    minHeight: 44,
    backgroundColor: C.card,
    borderRadius: 13,
    alignItems: 'center',
    justifyContent: 'center',
  },
  plus: { color: C.cyan, fontSize: 20, lineHeight: 22 },
  bookmarkText: { color: C.text, fontSize: 10, marginTop: 2 },
  dim: { opacity: 0.4 },
  failure: { color: '#FFAB95', fontSize: 11, marginBottom: 10 },

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
  sessionActions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 10,
    marginTop: 8,
  },
  sessionButton: {
    minWidth: 72,
    backgroundColor: C.cyan,
    minHeight: 44,
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: 13,
    borderRadius: 9,
  },
  deleteButton: { backgroundColor: C.coral },
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
    justifyContent: 'flex-end',
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
