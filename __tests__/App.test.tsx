import React from 'react';
import {
  Alert,
  DeviceEventEmitter,
  Modal,
  NativeModules,
  Share,
  Text,
  type AlertButton,
} from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import App from '../App';
import { AboutModal } from '../AboutModal';
import { ReleaseNotesModal } from '../ReleaseNotesModal';
import { FieldDefinitionsPanel } from '../FieldDefinitionsPanel';
import {
  DebugSettingsModal,
  DEFAULT_DEBUG_SETTINGS,
  parseDebugSettings,
} from '../DebugSettingsModal';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);
jest.mock('react-native', () => {
  const native = jest.requireActual('react-native');
  native.NativeModules.ARCaptureEngine = {
    getStatus: jest.fn(),
    getAppInfo: jest.fn(),
    startSession: jest.fn(),
    stopSession: jest.fn(),
    listSessions: jest.fn().mockResolvedValue([]),
    exportSession: jest.fn(),
    exportFieldWalk: jest.fn(),
    deleteSession: jest.fn(),
    clearMeasurements: jest.fn(),
    setSpatialMode: jest.fn(),
    completeFloorSetup: jest.fn(),
    setFloorVisible: jest.fn(),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
    setPreviewMode: jest.fn().mockResolvedValue(undefined),
    setDisplayZoom: jest.fn(),
    setDebugMode: jest.fn(),
    getDebugSettings: jest.fn(),
    setDebugSettings: jest.fn(),
    applyMeasuredTagSize: jest.fn(),
    getSavedFieldWalk: jest.fn(),
  };
  native.NativeModules.ArchiveModule = {
    archiveSession: jest.fn(),
    previewSession: jest.fn(),
    previewSessionAtTime: jest.fn(),
  };
  return native;
});

const engine = NativeModules.ARCaptureEngine;
let tree: Renderer.ReactTestRenderer;
beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  engine.listSessions.mockResolvedValue([]);
  engine.exportSession.mockReset();
  engine.exportFieldWalk.mockReset();
  engine.startSessionWithMode = undefined;
  engine.deleteSession.mockReset().mockResolvedValue(undefined);
  NativeModules.ArchiveModule.archiveSession.mockReset();
  NativeModules.ArchiveModule.previewSession.mockReset();
  NativeModules.ArchiveModule.previewSessionAtTime.mockReset();
  engine.getSavedFieldWalk.mockReset();
  engine.completeFloorSetup.mockReset();
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    lidarAvailable: true,
    depthAvailable: true,
    displayZoom: 1,
    spatial: {
      mode: 'distance',
      showFloorPlanes: false,
      floorSelected: true,
      floorId: 'fixture-floor',
      measurementCount: 0,
    },
  });
  engine.setDebugMode.mockImplementation(async (enabled: boolean) => {
    const status = await engine.getStatus();
    const next = {
      ...status,
      debugMode: enabled,
      spatial: {
        ...status.spatial,
        mode:
          !enabled && !status.spatial?.floorSelected
            ? 'selectFloor'
            : status.spatial?.mode || 'distance',
      },
    };
    engine.getStatus.mockResolvedValue(next);
    return next;
  });
  engine.getDebugSettings.mockResolvedValue(DEFAULT_DEBUG_SETTINGS);
  engine.setDisplayZoom.mockImplementation(async (displayZoom: number) => ({
    ...(await engine.getStatus()),
    displayZoom,
  }));
  engine.setSpatialMode.mockImplementation(async (mode: string) => {
    const status = await engine.getStatus();
    const next = {
      ...status,
      spatial: {
        ...status.spatial,
        mode:
          mode === 'selectFloor' ||
          !status.spatial?.floorSelected ||
          status.spatial?.mode === 'selectFloor'
            ? 'selectFloor'
            : mode,
      },
    };
    engine.getStatus.mockResolvedValue(next);
    return next;
  });
  engine.setFloorVisible.mockImplementation(
    async (showFloorPlanes: boolean) => {
      const status = await engine.getStatus();
      const next = {
        ...status,
        spatial: { ...status.spatial, showFloorPlanes },
      };
      engine.getStatus.mockResolvedValue(next);
      return next;
    },
  );
  engine.clearMeasurements.mockImplementation(async () => {
    const status = await engine.getStatus();
    const next = {
      ...status,
      spatial: { ...status.spatial, measurementCount: 0 },
      measurement: { pointCount: 0 },
    };
    engine.getStatus.mockResolvedValue(next);
    return next;
  });
  engine.getAppInfo.mockResolvedValue({
    bundleId: 'com.bionanomics.aprilfoolsar',
    version: '0.1.1',
    build: '6',
    buildCommit: '1234567890abcdef1234567890abcdef12345678',
    buildDateUTC: '2026-11-21T10:00:00Z',
    workingTreeDirty: false,
    releaseNotes: [
      {
        version: '0.1.1',
        build: '6',
        title: 'Build information',
        changes: ['Stamp recordings.'],
      },
    ],
  });
  engine.setDebugSettings.mockImplementation(
    async (settings: unknown) => settings,
  );
});
afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
  jest.useRealTimers();
  jest.restoreAllMocks();
});

const savedSession = {
  id: 'session-1',
  name: 'North field',
  createdAt: '2026-11-22T20:00:00Z',
  durationSeconds: 4,
  sizeBytes: 1024,
  finalized: true,
};

test('starts the selected facts-only mode and defaults new walks to video plus facts', async () => {
  engine.startSessionWithMode = jest.fn().mockResolvedValue(undefined);
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Video + facts' }).props
      .accessibilityState.selected,
  ).toBe(true);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Start recording' })
      .props.onPress(),
  );
  expect(engine.startSessionWithMode).toHaveBeenLastCalledWith(
    'Field walk',
    'video',
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Tag facts only' })
      .props.onPress(),
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag facts only' }).props
      .accessibilityState.selected,
  ).toBe(true);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Start recording' })
      .props.onPress(),
  );
  expect(engine.startSessionWithMode).toHaveBeenLastCalledWith(
    'Field walk',
    'facts',
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Bookmark' }).props.disabled,
  ).toBe(true);
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('shows remaining capacity with accessible exact metadata usage and locks recording mode', async () => {
  engine.getStatus.mockResolvedValue({
    recording: true,
    recordingMode: 'video',
    recordingCapacity: {
      usedBytes: 24 * 1048576,
      limitBytes: 32 * 1048576,
      remainingBytes: 8 * 1048576,
      fractionUsed: 0.75,
      limitingResource: 'Event metadata',
      estimatedSecondsRemaining: 18,
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const meter = tree.root.findByProps({
    accessibilityLabel: 'Recording capacity remaining',
  });
  expect(meter.props.accessibilityRole).toBe('progressbar');
  expect(meter.props.accessibilityValue).toEqual({
    min: 0,
    max: 100,
    now: 25,
    text: '25% remaining. Event metadata: 24.0 MiB of 32.0 MiB',
  });
  for (const label of ['Video + facts', 'Tag facts only']) {
    expect(
      tree.root.findByProps({ accessibilityLabel: label }).props.disabled,
    ).toBe(true);
  }
  expect(
    tree.root
      .findAllByType(Text)
      .some(node => node.props.children?.join?.('') === 'about 00:18 left'),
  ).toBe(true);
});

test('warns near capacity and labels package estimates without presenting records as bytes', async () => {
  engine.getStatus.mockResolvedValue({
    recording: true,
    recordingMode: 'facts',
    recordingCapacity: {
      usedBytes: 95000,
      limitBytes: 100000,
      remainingBytes: 5000,
      fractionUsed: 0.95,
      limitingResource: 'Walk observations',
      unit: 'records',
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Recording capacity remaining',
    }).props.accessibilityValue.text,
  ).toBe('5% remaining. Walk observations: 95,000 records of 100,000 records');
  expect(
    tree.root
      .findAllByType(Text)
      .some(
        node => node.props.children === 'Near the limit. Stop and save soon.',
      ),
  ).toBe(true);
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      recording: true,
      recordingCapacity: {
        usedBytes: 128 * 1048576,
        limitBytes: 256 * 1048576,
        remainingBytes: 128 * 1048576,
        fractionUsed: 0.5,
        limitingResource: 'Packaged recording',
        estimated: true,
      },
    }),
  );
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Recording capacity remaining',
    }).props.accessibilityValue.text,
  ).toBe(
    '50% remaining. Packaged recording (estimate): 128.0 MiB of 256.0 MiB',
  );
});

test('shares a facts-only walk as a YAML file and preserves tag review without video controls', async () => {
  engine.listSessions.mockResolvedValue([
    { ...savedSession, recordingMode: 'facts', summaryReady: true },
  ]);
  engine.exportFieldWalk.mockResolvedValue({
    url: 'file:///saved/walk.yaml',
    path: '/saved/walk.yaml',
    bytes: 1200,
  });
  const share = jest
    .spyOn(Share, 'share')
    .mockResolvedValue({ action: Share.sharedAction, activityType: undefined });
  await openSavedSessions();
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Play recording North field',
    }),
  ).toHaveLength(0);
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Field walk for North field',
    }).props.onPress,
  ).toEqual(expect.any(Function));
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Share YAML summary North field' })
      .props.onPress(),
  );
  expect(engine.exportFieldWalk).toHaveBeenCalledWith('session-1');
  expect(share).toHaveBeenCalledWith({
    url: 'file:///saved/walk.yaml',
    title: 'April Fools AR tag facts — North field',
  });
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Field walk for North field' })
      .props.onPress(),
  );
  expect(
    tree.root.findByType(FieldDefinitionsPanel).props.onOpenEvidence,
  ).toBeUndefined();
});

test('explains the automatic save threshold and disables bookmarks during a facts walk', async () => {
  const recordingCapacity = {
    usedBytes: 94000,
    limitBytes: 100000,
    remainingBytes: 6000,
    fractionUsed: 0.94,
    limitingResource: 'Tag facts summary',
    unit: 'bytes',
    automaticSaveFraction: 0.95,
  };
  engine.getStatus.mockResolvedValue({
    recording: true,
    recordingMode: 'facts',
    recordingCapacity,
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Bookmark' }).props.disabled,
  ).toBe(true);
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Recording capacity remaining',
    }).props.accessibilityValue.text,
  ).toContain('Auto-save at 95% used.');
  expect(
    tree.root
      .findAllByType(Text)
      .some(
        node =>
          node.props.children ===
          'Near the limit. Saves automatically at 95% used.',
      ),
  ).toBe(true);
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      recording: true,
      recordingMode: 'facts',
      recordingCapacity: { ...recordingCapacity, fractionUsed: 0.95 },
    }),
  );
  expect(
    tree.root
      .findAllByType(Text)
      .some(node => node.props.children === 'Saving automatically…'),
  ).toBe(true);
});

async function openSavedSessions() {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Saved sessions' })
      .props.onPress(),
  );
}

async function openMoreControls() {
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'More controls' })
      .props.onPress(),
  );
}

async function openDebugSettings() {
  if (tree.root.findAllByProps({ testID: 'capture.toolSheet' }).length > 0) {
    await act(async () =>
      tree.root
        .findByProps({ accessibilityLabel: 'Close capture tools' })
        .props.onPress(),
    );
  }
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
}

async function editSessionName(name: string) {
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Edit session name' })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Session name' })
      .props.onChangeText(name),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Close capture tools' })
      .props.onPress(),
  );
}

const visibleNativeModals = () =>
  tree.root.findAllByType(Modal).filter(modal => modal.props.visible === true);

async function closeVersionPage() {
  const page = tree.root.findByType(ReleaseNotesModal);
  await act(async () =>
    page
      .findByProps({ accessibilityLabel: 'Close release notes' })
      .props.onPress(),
  );
  await act(async () => page.findByType(Modal).props.onDismiss());
}

function deletionButtons(alert: jest.SpyInstance) {
  const call = alert.mock.calls
    .filter(([title]) => title === 'Delete recording?')
    .pop();
  expect(call).toBeDefined();
  const buttons = call![2] as AlertButton[];
  const cancel = buttons.find(button => button.style === 'cancel');
  const confirm = buttons.find(button => button.style === 'destructive');
  expect(cancel?.text).toBe('Cancel');
  expect(confirm?.text).toBe('Delete');
  return { cancel: cancel!, confirm: confirm! };
}

test('explains permanent deletion and cancels without removing the recording', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Delete recording North field' })
      .props.onPress(),
  );
  expect(engine.deleteSession).not.toHaveBeenCalled();
  const confirmation = alert.mock.calls[0];
  expect(confirmation[0]).toBe('Delete recording?');
  expect(confirmation[1]).toContain('North field');
  expect(confirmation[1]).toMatch(/permanent|cannot be undone/i);
  expect(confirmation[1]).toMatch(/video|MP4/i);
  expect(confirmation[1]).toMatch(/original|capture data/i);
  const { cancel } = deletionButtons(alert);
  for (const action of ['Play', 'Share', 'Delete']) {
    const button = tree.root.findByProps({
      accessibilityLabel: `${action} recording North field`,
    });
    expect(button.props.disabled).toBe(true);
    expect(button.props.accessibilityState.disabled).toBe(true);
    await act(async () => button.props.onPress());
  }
  expect(alert).toHaveBeenCalledTimes(1);
  expect(engine.exportSession).not.toHaveBeenCalled();
  await act(async () => cancel.onPress?.());
  expect(engine.deleteSession).not.toHaveBeenCalled();
  for (const action of ['Play', 'Share', 'Delete']) {
    expect(
      tree.root.findByProps({
        accessibilityLabel: `${action} recording North field`,
      }).props.disabled,
    ).toBe(false);
  }
});

test('releases the action lock when Android dismisses deletion without confirmation', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  const remove = () =>
    tree.root.findByProps({
      accessibilityLabel: 'Delete recording North field',
    });
  await act(async () => remove().props.onPress());
  const options = alert.mock.calls[0][3] as NonNullable<
    Parameters<typeof Alert.alert>[3]
  >;
  expect(options.cancelable).toBe(true);
  await act(async () => options.onDismiss?.());
  expect(engine.deleteSession).not.toHaveBeenCalled();
  for (const action of ['Play', 'Share', 'Delete']) {
    expect(
      tree.root.findByProps({
        accessibilityLabel: `${action} recording North field`,
      }).props.disabled,
    ).toBe(false);
  }
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Refresh saved sessions' })
      .props.disabled,
  ).toBe(false);
  await act(async () => remove().props.onPress());
  expect(alert).toHaveBeenCalledTimes(2);
  await act(async () => deletionButtons(alert).cancel.onPress?.());
});

test('retains the action lock when Android dismisses a confirmed deletion alert', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  let finish!: () => void;
  engine.deleteSession.mockImplementation(
    () =>
      new Promise<void>(resolve => {
        finish = resolve;
      }),
  );
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Delete recording North field' })
      .props.onPress(),
  );
  const options = alert.mock.calls[0][3] as NonNullable<
    Parameters<typeof Alert.alert>[3]
  >;
  await act(async () => {
    deletionButtons(alert).confirm.onPress?.();
  });
  await act(async () => options.onDismiss?.());
  expect(engine.deleteSession).toHaveBeenCalledTimes(1);
  for (const action of ['Play', 'Share', 'Delete']) {
    const button = tree.root.findByProps({
      accessibilityLabel: `${action} recording North field`,
    });
    expect(button.props.disabled).toBe(true);
    await act(async () => button.props.onPress());
  }
  const refresh = tree.root.findByProps({
    accessibilityLabel: 'Refresh saved sessions',
  });
  expect(refresh.props.disabled).toBe(true);
  await act(async () => refresh.props.onPress());
  expect(engine.listSessions).toHaveBeenCalledTimes(1);
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(alert).toHaveBeenCalledTimes(1);
  expect(
    tree.root.findAllByProps({ children: 'Deleting recording…' }),
  ).not.toHaveLength(0);
  await act(async () => finish());
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Refresh saved sessions' })
      .props.disabled,
  ).toBe(false);
});

test('deletes only the confirmed session and removes its card after success', async () => {
  const otherSession = {
    ...savedSession,
    id: 'session-2',
    name: 'South field',
  };
  engine.listSessions
    .mockResolvedValueOnce([savedSession, otherSession])
    .mockResolvedValue([otherSession]);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Delete recording North field' })
      .props.onPress(),
  );
  expect(engine.deleteSession).not.toHaveBeenCalled();
  await act(async () => deletionButtons(alert).confirm.onPress?.());
  expect(engine.deleteSession).toHaveBeenCalledTimes(1);
  expect(engine.deleteSession).toHaveBeenCalledWith('session-1');
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Delete recording North field',
    }),
  ).toHaveLength(0);
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Delete recording South field',
    }).props.disabled,
  ).toBe(false);
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
});

test('ignores a pending refresh that returns the deleted recording after deletion completes', async () => {
  const otherSession = {
    ...savedSession,
    id: 'session-2',
    name: 'South field',
  };
  let completeRefresh!: (sessions: (typeof savedSession)[]) => void;
  engine.listSessions
    .mockResolvedValueOnce([savedSession, otherSession])
    .mockImplementationOnce(
      () =>
        new Promise(resolve => {
          completeRefresh = resolve;
        }),
    );
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Refresh saved sessions' })
      .props.onPress();
  });
  expect(engine.listSessions).toHaveBeenCalledTimes(2);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Delete recording North field' })
      .props.onPress(),
  );
  await act(async () => deletionButtons(alert).confirm.onPress?.());
  expect(engine.deleteSession).toHaveBeenCalledWith('session-1');
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Delete recording North field',
    }),
  ).toHaveLength(0);
  await act(async () => completeRefresh([savedSession, otherSession]));
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Delete recording North field',
    }),
  ).toHaveLength(0);
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Delete recording South field',
    }).props.disabled,
  ).toBe(false);
});

test('preserves the session on deletion failure and permits retry', async () => {
  engine.listSessions
    .mockResolvedValueOnce([savedSession])
    .mockResolvedValue([]);
  engine.deleteSession
    .mockRejectedValueOnce(new Error('Unable to remove recording'))
    .mockResolvedValueOnce(undefined);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  const remove = () =>
    tree.root.findByProps({
      accessibilityLabel: 'Delete recording North field',
    });
  await act(async () => remove().props.onPress());
  await act(async () => deletionButtons(alert).confirm.onPress?.());
  expect(alert).toHaveBeenCalledWith(
    'Delete recording',
    'Unable to remove recording',
  );
  expect(remove().props.disabled).toBe(false);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.disabled,
  ).toBe(false);
  await act(async () => remove().props.onPress());
  await act(async () => deletionButtons(alert).confirm.onPress?.());
  expect(engine.deleteSession).toHaveBeenCalledTimes(2);
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Delete recording North field',
    }),
  ).toHaveLength(0);
});

test('allows an old unfinished recording to be deleted without trying to export it', async () => {
  engine.listSessions
    .mockResolvedValueOnce([{ ...savedSession, finalized: false }])
    .mockResolvedValue([]);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  const remove = tree.root.findByProps({
    accessibilityLabel: 'Delete recording North field',
  });
  expect(remove.props.disabled).toBe(false);
  await act(async () => remove.props.onPress());
  await act(async () => deletionButtons(alert).confirm.onPress?.());
  expect(engine.deleteSession).toHaveBeenCalledWith('session-1');
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
});

test.each([
  { recording: true, finalizing: false },
  { recording: false, finalizing: true },
])('protects the current session while %j', async captureStatus => {
  engine.listSessions.mockResolvedValue([
    { ...savedSession, finalized: false },
  ]);
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...captureStatus,
      sessionId: savedSession.id,
      tracking: 'normal',
    });
  });
  const remove = tree.root.findByProps({
    accessibilityLabel: 'Delete recording North field',
  });
  expect(remove.props.disabled).toBe(true);
  expect(remove.props.accessibilityState.disabled).toBe(true);
  await act(async () => remove.props.onPress());
  expect(engine.deleteSession).not.toHaveBeenCalled();
  expect(alert).not.toHaveBeenCalled();
});

test('locks saved-session actions and reports progress until deletion finishes', async () => {
  const otherSession = {
    ...savedSession,
    id: 'session-2',
    name: 'South field',
  };
  engine.listSessions
    .mockResolvedValueOnce([savedSession, otherSession])
    .mockResolvedValue([otherSession]);
  let finish!: () => void;
  engine.deleteSession.mockImplementation(
    () =>
      new Promise<void>(resolve => {
        finish = resolve;
      }),
  );
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Delete recording North field' })
      .props.onPress(),
  );
  await act(async () => {
    deletionButtons(alert).confirm.onPress?.();
  });
  expect(engine.deleteSession).toHaveBeenCalledTimes(1);
  expect(
    tree.root.findAllByProps({ children: 'Deleting recording…' }),
  ).not.toHaveLength(0);
  for (const name of ['North field', 'South field']) {
    for (const action of ['Play', 'Share', 'Delete']) {
      const button = tree.root.findByProps({
        accessibilityLabel: `${action} recording ${name}`,
      });
      expect(button.props.disabled).toBe(true);
      await act(async () => button.props.onPress());
    }
  }
  expect(engine.deleteSession).toHaveBeenCalledTimes(1);
  expect(engine.exportSession).not.toHaveBeenCalled();
  await act(async () => {
    DeviceEventEmitter.emit('url', { url: 'aprilfoolsar://capture/start' });
    jest.advanceTimersByTime(1200);
  });
  expect(engine.startSession).not.toHaveBeenCalled();
  await act(async () => finish());
  expect(
    tree.root.findAllByProps({ children: 'Deleting recording…' }),
  ).toHaveLength(0);
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Delete recording South field',
    }).props.disabled,
  ).toBe(false);
});

test('plays the validated saved session in the native player', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({
    finalized: true,
    folderPath: '/sessions/session-1',
  });
  NativeModules.ArchiveModule.previewSession.mockResolvedValue(undefined);
  await openSavedSessions();
  expect(
    tree.root.findAllByProps({ testID: 'capture.native-camera' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.onPress(),
  );
  expect(engine.exportSession).toHaveBeenCalledWith('session-1');
  expect(NativeModules.ArchiveModule.previewSession).toHaveBeenCalledWith(
    '/sessions/session-1',
  );
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
});

test('opens a tag observation at its recorded time after the field modal finishes dismissing', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({
    finalized: true,
    folderPath: '/sessions/session-1',
  });
  engine.getSavedFieldWalk.mockResolvedValue({
    yaml: 'schemaVersion: 1\n',
    field: {
      seenTags: [
        {
          id: 4,
          frameId: 'source-frame',
          segmentId: 'source-segment',
          timestamp: 121.125,
          videoTimeSeconds: 1.125,
        },
      ],
    },
  });
  NativeModules.ArchiveModule.previewSessionAtTime.mockResolvedValue(undefined);
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Field walk for North field' })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Open observation for tag 4' })
      .props.onPress(),
  );
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(
    NativeModules.ArchiveModule.previewSessionAtTime,
  ).not.toHaveBeenCalled();
  await act(async () =>
    tree.root.findByType(FieldDefinitionsPanel).props.onDismiss(),
  );
  expect(engine.exportSession).toHaveBeenCalledWith('session-1');
  expect(NativeModules.ArchiveModule.previewSessionAtTime).toHaveBeenCalledWith(
    '/sessions/session-1',
    1.125,
  );
  expect(NativeModules.ArchiveModule.previewSession).not.toHaveBeenCalled();
});

test('field tools retain the live camera, block background tag taps and return to floor setup', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = tree.root.findByProps({ testID: 'capture.native-camera' });
  const navigation = tree.root.findByProps({ testID: 'capture.navigation' });
  await act(async () =>
    navigation
      .findByProps({ accessibilityLabel: 'Field definitions and tags seen' })
      .props.onPress(),
  );
  expect(tree.root.findByType(FieldDefinitionsPanel).props.visible).toBe(true);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
  });
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root.findByType(FieldDefinitionsPanel).props.onSetFloor(),
  );
  expect(tree.root.findByType(FieldDefinitionsPanel).props.visible).toBe(false);
  expect(tree.root.findByProps({ testID: 'capture.native-camera' })).toBe(
    camera,
  );
  expect(engine.setSpatialMode).toHaveBeenCalledWith('selectFloor');
  expect(engine.setDebugMode).toHaveBeenCalledWith(false);
  expect(tree.root.findByProps({ testID: 'capture.toolSheet' })).toBeTruthy();
  expect(JSON.stringify(tree.toJSON())).toContain('Floor setup');
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('shares the reusable native MP4 from a finalized saved session', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({
    finalized: true,
    folderPath: '/sessions/session-1',
  });
  NativeModules.ArchiveModule.archiveSession.mockResolvedValue({
    url: 'file:///recordings/session-1.mp4',
    format: 'mp4',
    mimeType: 'video/mp4',
  });
  const share = jest
    .spyOn(Share, 'share')
    .mockResolvedValue({ action: Share.sharedAction, activityType: undefined });
  await openSavedSessions();
  expect(tree.root.findAllByProps({ children: 'Export MP4 ↗' })).toHaveLength(
    0,
  );
  for (let attempt = 0; attempt < 2; attempt++) {
    await act(async () =>
      tree.root
        .findByProps({ accessibilityLabel: 'Share recording North field' })
        .props.onPress(),
    );
  }
  expect(engine.exportSession).toHaveBeenCalledWith('session-1');
  expect(NativeModules.ArchiveModule.archiveSession).toHaveBeenCalledWith(
    '/sessions/session-1',
  );
  expect(share).toHaveBeenCalledWith({
    url: 'file:///recordings/session-1.mp4',
    title: 'April Fools AR by The REFINERY — North field',
  });
  expect(share).toHaveBeenCalledTimes(2);
  expect(NativeModules.ArchiveModule.previewSession).not.toHaveBeenCalled();
});

test('does not open a recording that is no longer finalized', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({ finalized: false });
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.onPress(),
  );
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.previewSession).not.toHaveBeenCalled();
  expect(alert).toHaveBeenCalledWith(
    'Play recording',
    'Stop and save the recording first.',
  );
});

test('disables Play and Share for unfinished saved recordings', async () => {
  engine.listSessions.mockResolvedValue([
    { ...savedSession, finalized: false },
  ]);
  jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  for (const action of ['Play', 'Share']) {
    const button = tree.root.findByProps({
      accessibilityLabel: `${action} recording North field`,
    });
    expect(button.props.disabled).toBe(true);
    expect(button.props.accessibilityState.disabled).toBe(true);
    await act(async () => button.props.onPress());
  }
  expect(engine.exportSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.previewSession).not.toHaveBeenCalled();
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
});

test('keeps saved-session controls disabled until the player is dismissed', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({
    finalized: true,
    folderPath: '/sessions/session-1',
  });
  let dismiss!: () => void;
  NativeModules.ArchiveModule.previewSession.mockImplementation(
    () =>
      new Promise<void>(resolve => {
        dismiss = resolve;
      }),
  );
  await openSavedSessions();
  const play = tree.root.findByProps({
    accessibilityLabel: 'Play recording North field',
  });
  await act(async () => {
    void play.props.onPress();
    void play.props.onPress();
  });
  expect(NativeModules.ArchiveModule.previewSession).toHaveBeenCalledTimes(1);
  expect(
    tree.root.findAllByProps({ children: 'Opening recording…' }),
  ).not.toHaveLength(0);
  for (const action of ['Play', 'Share', 'Delete']) {
    expect(
      tree.root.findByProps({
        accessibilityLabel: `${action} recording North field`,
      }).props.disabled,
    ).toBe(true);
  }
  await act(async () => {
    DeviceEventEmitter.emit('url', { url: 'aprilfoolsar://capture/start' });
    jest.advanceTimersByTime(1200);
  });
  expect(engine.startSession).not.toHaveBeenCalled();
  expect(
    tree.root.findAllByProps({ testID: 'capture.native-camera' }),
  ).toHaveLength(0);
  await act(async () => dismiss());
  expect(
    tree.root.findAllByProps({ children: 'Opening recording…' }),
  ).toHaveLength(0);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.disabled,
  ).toBe(false);
});

test.each(['Play', 'Share'])(
  '%s reports native preparation failures and restores the controls',
  async action => {
    engine.listSessions.mockResolvedValue([savedSession]);
    engine.exportSession.mockResolvedValue({
      finalized: true,
      folderPath: '/sessions/session-1',
    });
    const method = action === 'Play' ? 'previewSession' : 'archiveSession';
    NativeModules.ArchiveModule[method].mockRejectedValue(
      new Error('Missing saved MP4'),
    );
    const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
    const share = jest.spyOn(Share, 'share');
    await openSavedSessions();
    await act(async () =>
      tree.root
        .findByProps({ accessibilityLabel: `${action} recording North field` })
        .props.onPress(),
    );
    expect(alert).toHaveBeenCalledWith(
      `${action} recording`,
      'Missing saved MP4',
    );
    expect(share).not.toHaveBeenCalled();
    expect(
      tree.root.findByProps({
        accessibilityLabel: `${action} recording North field`,
      }).props.disabled,
    ).toBe(false);
  },
);

test('reports session lookup failure without opening the native player', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockRejectedValue(new Error('Session not found'));
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.onPress(),
  );
  expect(alert).toHaveBeenCalledWith('Play recording', 'Session not found');
  expect(NativeModules.ArchiveModule.previewSession).not.toHaveBeenCalled();
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Play recording North field' })
      .props.disabled,
  ).toBe(false);
});

test('rejects a finalized session with no validated folder', async () => {
  engine.listSessions.mockResolvedValue([savedSession]);
  engine.exportSession.mockResolvedValue({ finalized: true });
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await openSavedSessions();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Share recording North field' })
      .props.onPress(),
  );
  expect(alert).toHaveBeenCalledWith(
    'Share recording',
    'The saved recording could not be found.',
  );
  expect(NativeModules.ArchiveModule.archiveSession).not.toHaveBeenCalled();
});

test('shows the saved MP4 size when it is ready', async () => {
  engine.listSessions.mockResolvedValue([
    { ...savedSession, recordingReady: true, recordingBytes: 2 * 1048576 },
  ]);
  await openSavedSessions();
  expect(
    tree.root.findAll(
      node =>
        Array.isArray(node.props.children) &&
        node.props.children.includes('2.0 MB'),
    ),
  ).not.toHaveLength(0);
});

test('explains how to retry an MP4 preparation failure after saving', async () => {
  engine.getStatus.mockResolvedValue({ recording: true });
  engine.stopSession.mockImplementation(async () => {
    engine.getStatus.mockResolvedValue({ recording: false });
    return { recordingReady: false, recordingError: 'Disk full' };
  });
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Stop and save recording' })
      .props.onPress(),
  );
  expect(alert).toHaveBeenCalledWith(
    'Recording saved',
    'The original recording was saved, but its MP4 is not ready yet. Tap Play or Share in Saved sessions to retry.\n\nDisk full',
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Start recording' }).props
      .disabled,
  ).toBe(false);
});

test('starts a named native recording and stops it using the same control', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await editSessionName('North field');
  engine.startSession.mockImplementation(async () => {
    engine.getStatus.mockResolvedValue({
      recording: true,
      tracking: 'normal',
      depthAvailable: true,
    });
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Start recording' })
      .props.onPress(),
  );
  expect(engine.startSession).toHaveBeenCalledWith('North field');
  engine.stopSession.mockImplementation(async () => {
    engine.getStatus.mockResolvedValue({
      recording: false,
      tracking: 'normal',
    });
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Stop and save recording' })
      .props.onPress(),
  );
  expect(engine.stopSession).toHaveBeenCalledTimes(1);
});

test.each(['badge', 'More menu'])(
  '%s opens the full-screen Version page with bottom navigation and installed build details',
  async entryPoint => {
    await act(async () => {
      tree = Renderer.create(<App />);
    });
    if (entryPoint === 'More menu') {
      await openMoreControls();
      expect(JSON.stringify(tree.toJSON())).toContain('v0.1.1 (6) · 1234567');
    }
    await act(async () =>
      tree.root
        .findByProps({
          accessibilityLabel:
            entryPoint === 'badge'
              ? 'Open version and release notes'
              : 'Version and release notes',
        })
        .props.onPress(),
    );
    const page = tree.root.findByType(ReleaseNotesModal);
    expect(page.props.visible).toBe(true);
    const modal = page.findByType(Modal);
    expect(modal.props.presentationStyle).toBe('overFullScreen');
    expect(visibleNativeModals()).toEqual([modal]);
    const contents = JSON.stringify(tree.toJSON());
    expect(contents).toContain('1234567890abcdef1234567890abcdef12345678');
    expect(contents).toContain('2026-11-21T10:00:00Z');
    const navigation = page.findByProps({ testID: 'release.notes.navigation' });
    expect(
      navigation.findByProps({ accessibilityLabel: 'Version' }).props
        .accessibilityState.selected,
    ).toBe(true);
    await act(async () =>
      navigation
        .findByProps({ accessibilityLabel: 'Release notes' })
        .props.onPress(),
    );
    expect(page.findByProps({ testID: 'current-release' })).toBeTruthy();
    expect(
      navigation.findByProps({ accessibilityLabel: 'Release notes' }).props
        .accessibilityState.selected,
    ).toBe(true);
    await closeVersionPage();
    expect(visibleNativeModals()).toHaveLength(0);
    expect(
      tree.root.findByProps({ testID: 'capture.native-camera' }),
    ).toBeTruthy();
    expect(engine.startSession).not.toHaveBeenCalled();
  },
);

test.each(['About', 'Settings', 'Bookmark'])(
  'the %s badge waits for native dismissal before presenting Version',
  async source => {
    if (source === 'Bookmark') {
      engine.getStatus.mockResolvedValue({
        ...(await engine.getStatus()),
        recording: true,
      });
    }
    await act(async () => {
      tree = Renderer.create(<App />);
    });
    if (source === 'About') {
      await openMoreControls();
      await act(async () =>
        tree.root
          .findByProps({ accessibilityLabel: 'About and sponsors' })
          .props.onPress(),
      );
    } else if (source === 'Settings') {
      await openDebugSettings();
    } else {
      await act(async () =>
        tree.root
          .findByProps({ accessibilityLabel: 'Bookmark' })
          .props.onPress(),
      );
    }
    const currentModal = visibleNativeModals()[0];
    expect(visibleNativeModals()).toHaveLength(1);
    const pressBadge = currentModal.findByProps({
      accessibilityLabel: 'Open version and release notes',
    }).props.onPress;
    const previousInfoRequests = engine.getAppInfo.mock.calls.length;
    await act(async () => {
      pressBadge();
      pressBadge();
    });
    expect(currentModal.props.visible).toBe(false);
    expect(tree.root.findByType(ReleaseNotesModal).props.visible).toBe(false);
    expect(visibleNativeModals()).toHaveLength(0);
    expect(engine.getAppInfo).toHaveBeenCalledTimes(previousInfoRequests + 1);
    await act(async () => {
      DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
    });
    expect(
      tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
    ).toHaveLength(0);
    await act(async () => currentModal.props.onDismiss());
    const versionModal = tree.root
      .findByType(ReleaseNotesModal)
      .findByType(Modal);
    expect(versionModal.props.visible).toBe(true);
    expect(versionModal.props.presentationStyle).toBe('overFullScreen');
    expect(visibleNativeModals()).toEqual([versionModal]);
    await closeVersionPage();
    expect(visibleNativeModals()).toHaveLength(0);
    expect(engine.setDebugSettings).not.toHaveBeenCalled();
    expect(engine.stopSession).not.toHaveBeenCalled();
  },
);

test('repeated version taps are coalesced while open and during native dismissal', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const pressBadge = tree.root.findByProps({
    accessibilityLabel: 'Open version and release notes',
  }).props.onPress;
  const previousInfoRequests = engine.getAppInfo.mock.calls.length;
  await act(async () => {
    pressBadge();
    pressBadge();
  });
  expect(engine.getAppInfo).toHaveBeenCalledTimes(previousInfoRequests + 1);
  expect(visibleNativeModals()).toHaveLength(1);
  await act(async () => pressBadge());
  expect(engine.getAppInfo).toHaveBeenCalledTimes(previousInfoRequests + 1);
  const page = tree.root.findByType(ReleaseNotesModal);
  await act(async () =>
    page
      .findByProps({ accessibilityLabel: 'Close release notes' })
      .props.onPress(),
  );
  await act(async () => pressBadge());
  expect(page.props.visible).toBe(false);
  expect(visibleNativeModals()).toHaveLength(0);
  expect(engine.getAppInfo).toHaveBeenCalledTimes(previousInfoRequests + 1);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
  });
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () => page.findByType(Modal).props.onDismiss());
  await act(async () => pressBadge());
  expect(page.props.visible).toBe(true);
  expect(engine.getAppInfo).toHaveBeenCalledTimes(previousInfoRequests + 2);
});

test('opening Version preserves the active recording, camera, zoom and filter preference', async () => {
  engine.getStatus.mockResolvedValue({
    ...(await engine.getStatus()),
    recording: true,
    displayZoom: 2,
    aprilTag: {
      debugSettings: {
        ...DEFAULT_DEBUG_SETTINGS,
        kalmanFilterEnabled: true,
        kalmanFilterSamples: 20,
      },
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = tree.root.findByProps({ testID: 'capture.native-camera' });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Open version and release notes' })
      .props.onPress(),
  );
  expect(tree.root.findByType(ReleaseNotesModal).props.visible).toBe(true);
  await closeVersionPage();
  expect(tree.root.findByProps({ testID: 'capture.native-camera' })).toBe(
    camera,
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Stop and save recording' })
      .props.disabled,
  ).toBe(false);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'View zoom 2×' }).props
      .accessibilityState.selected,
  ).toBe(true);
  const filter = tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  expect(filter.props.accessibilityState.checked).toBe(true);
  expect(filter.props.accessibilityValue.text).toBe('20 samples');
  expect(engine.startSession).not.toHaveBeenCalled();
  expect(engine.stopSession).not.toHaveBeenCalled();
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
});

test('installed version stays visible in live capture, tool panels and saved recordings', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const expectVersionBadge = () => {
    const badge = tree.root.findByProps({ testID: 'app.versionBadge' });
    expect(
      badge.findByProps({ accessibilityLabel: 'Installed app version' }).props
        .children,
    ).toBe('v0.1.1 (6)');
  };
  expectVersionBadge();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Tag details' })
      .props.onPress(),
  );
  expectVersionBadge();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Close capture tools' })
      .props.onPress(),
  );
  await openMoreControls();
  expectVersionBadge();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Close capture tools' })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expectVersionBadge();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Close capture tools' })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Saved sessions' })
      .props.onPress(),
  );
  expectVersionBadge();
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('explicit native tag taps open details and the same tag can reopen them after closing', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  for (const id of [4, 4, 0]) {
    expect(
      tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
    ).toHaveLength(0);
    await act(async () => {
      DeviceEventEmitter.emit('ARCaptureTagSelected', { id });
    });
    expect(
      tree.root.findByProps({ testID: 'capture.tagReadout' }),
    ).toBeTruthy();
    expect(
      tree.root.findByProps({ accessibilityLabel: 'Start recording' }).props
        .disabled,
    ).toBe(false);
    await act(async () =>
      tree.root
        .findByProps({ accessibilityLabel: 'Close capture tools' })
        .props.onPress(),
    );
  }
  expect(engine.startSession).not.toHaveBeenCalled();
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
});

test('malformed native tag selection events leave the current screen unchanged', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  for (const payload of [
    {},
    { id: -1 },
    { id: 1.5 },
    { id: '4' },
    { id: true },
    { id: null },
    { id: NaN },
    { id: Infinity },
    { id: Number.MAX_SAFE_INTEGER + 1 },
  ]) {
    await act(async () => {
      DeviceEventEmitter.emit('ARCaptureTagSelected', payload);
    });
    expect(
      tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
    ).toHaveLength(0);
    expect(
      tree.root.findAllByProps({ testID: 'capture.toolSheet' }),
    ).toHaveLength(0);
  }
});

test('queued tag selection events do not replace saved recordings or an open settings modal', async () => {
  await openSavedSessions();
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
  });
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Saved sessions' }).props
      .accessibilityState.selected,
  ).toBe(true);
  expect(
    tree.root.findAllByProps({ testID: 'capture.native-camera' }),
  ).toHaveLength(0);
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Tag debug mode' })
      .props.onPress(),
  );
  await openDebugSettings();
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
  });
  expect(tree.root.findByType(DebugSettingsModal).props.visible).toBe(true);
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root.findByType(DebugSettingsModal).props.onCancel(),
  );
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 4 });
  });
  expect(tree.root.findByProps({ testID: 'capture.tagReadout' })).toBeTruthy();
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
});

test('automatic and stale tag status never open or reopen the details sheet', async () => {
  const initial = await engine.getStatus();
  engine.getStatus.mockResolvedValue({
    ...initial,
    aprilTag: { state: 'running', ids: [4], selectedId: 4 },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...initial,
      aprilTag: { state: 'running', ids: [17], selectedId: 17 },
    });
  });
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureTagSelected', { id: 17 });
  });
  expect(tree.root.findByProps({ testID: 'capture.tagReadout' })).toBeTruthy();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Close capture tools' })
      .props.onPress(),
  );
  for (const aprilTag of [
    { state: 'waiting', ids: [], selectedId: 17, ageMilliseconds: 5000 },
    { state: 'error', ids: [], selectedId: -1, error: 'Stale result' },
    { state: 'running', ids: [4], selectedId: 4 },
  ]) {
    await act(async () => {
      DeviceEventEmitter.emit('ARCaptureStatus', { ...initial, aprilTag });
    });
    expect(
      tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
    ).toHaveLength(0);
  }
});

test('More opens the full-screen About and sponsors page with bottom privacy and license tabs', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'About and sponsors' }),
  ).toHaveLength(0);
  await openMoreControls();
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Sponsors' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'About and sponsors' })
      .props.onPress(),
  );
  const about = tree.root.findByType(AboutModal);
  expect(about.findByType(Modal).props.presentationStyle).toBe(
    'overFullScreen',
  );
  expect(visibleNativeModals()).toEqual([about.findByType(Modal)]);
  expect(JSON.stringify(tree.toJSON())).toContain('Don Wood Foundation');
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Medical Informatics Engineering',
  );
  const navigation = about.findByProps({ testID: 'about.bottomNav' });
  const pressAboutTab = async (title: string) => {
    const tab = navigation
      .findAllByProps({ accessibilityRole: 'tab' })
      .find(node =>
        node.findAllByType(Text).some(label => label.props.children === title),
      );
    expect(tab).toBeDefined();
    await act(async () => tab!.props.onPress());
  };
  await pressAboutTab('Privacy');
  expect(about.findByProps({ testID: 'privacy-policy' })).toBeTruthy();
  await pressAboutTab('Licenses & notices');
  expect(about.findByProps({ testID: 'app-license' })).toBeTruthy();
  expect(about.findByProps({ testID: 'third-party-notices' })).toBeTruthy();
  await act(async () =>
    about
      .findByProps({ accessibilityLabel: 'Close about and privacy' })
      .props.onPress(),
  );
  await act(async () => about.findByType(Modal).props.onDismiss());
  expect(visibleNativeModals()).toHaveLength(0);
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('bottom Saved and Tags tabs switch between the recordings list and live camera', async () => {
  await openSavedSessions();
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Saved sessions' }).props
      .accessibilityState.selected,
  ).toBe(true);
  expect(
    tree.root.findAllByProps({ testID: 'capture.native-camera' }),
  ).toHaveLength(0);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Tag debug mode' })
      .props.onPress(),
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag debug mode' }).props
      .accessibilityState.selected,
  ).toBe(true);
  expect(
    tree.root.findAllByProps({ testID: 'capture.native-camera' }),
  ).not.toHaveLength(0);
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('falls back to a nonempty session name when the input is blank', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await editSessionName('  ');
  engine.startSession.mockResolvedValue(undefined);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Start recording' })
      .props.onPress(),
  );
  expect(engine.startSession).toHaveBeenCalledWith('Field walk');
});

test('measurement mode shows current native tag IDs before recording and clears absent tags', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    aprilTag: { state: 'running', family: 'tag36h11', ids: [4, 17] },
    spatial: { mode: 'distance', floorSelected: true },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('Visible: #4, #17');
  expect(engine.startSession).not.toHaveBeenCalled();

  engine.getStatus.mockResolvedValue({
    recording: false,
    aprilTag: { state: 'ready', family: 'tag36h11', ids: [] },
    spatial: { mode: 'distance', floorSelected: true },
  });
  await act(async () => jest.advanceTimersByTime(2000));
  expect(JSON.stringify(tree.toJSON())).toContain('Looking for tags');
  expect(JSON.stringify(tree.toJSON())).not.toContain('Visible: #4, #17');
});

test('debug settings convert displayed millimeters and centimeters to native meters', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Custom width' })
      .props.onPress(),
  );
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Tag width (mm)' })
      .props.onChangeText('200');
    tree.root
      .findByProps({ accessibilityLabel: 'Depth warning (cm)' })
      .props.onChangeText('8');
    tree.root
      .findByProps({ accessibilityLabel: 'Depth rejection (cm)' })
      .props.onChangeText('12');
    tree.root
      .findByProps({ accessibilityLabel: 'Distance delta threshold (cm)' })
      .props.onChangeText('21.5');
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.2,
    tagSizeMode: 'custom',
    warningDepthDifferenceMeters: 0.08,
    rejectDepthDifferenceMeters: 0.12,
    distanceDeltaThresholdMeters: 0.215,
  });
});

test('live Kalman checkbox toggles in both directions without opening Settings or rewriting calibration', async () => {
  const saved = {
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.1723456789,
    tagSizeSource: 'ar-two-point-edge',
    kalmanFilterEnabled: false,
    kalmanFilterSamples: 20,
    maxDistanceMeters: 7,
    levelFloorWithGravity: true,
  };
  const nativeStatus = await engine.getStatus();
  engine.getStatus.mockResolvedValue({
    ...nativeStatus,
    aprilTag: { debugSettings: saved },
  });
  engine.setDebugSettings.mockImplementation(async (patch: object) => ({
    ...saved,
    ...patch,
  }));
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  expect(toggle().props.accessibilityRole).toBe('checkbox');
  expect(toggle().props.accessibilityState.checked).toBe(false);
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Smoothing strength' }),
  ).toHaveLength(0);
  expect(engine.getDebugSettings).not.toHaveBeenCalled();
  await act(async () => toggle().props.onPress());
  expect(engine.setDebugSettings).toHaveBeenNthCalledWith(1, {
    kalmanFilterEnabled: true,
  });
  expect(toggle().props.accessibilityState.checked).toBe(true);
  expect(
    tree.root.findByType(DebugSettingsModal).props.initialSettings,
  ).toEqual({ ...saved, kalmanFilterEnabled: true });
  await act(async () => toggle().props.onPress());
  expect(engine.setDebugSettings).toHaveBeenNthCalledWith(2, {
    kalmanFilterEnabled: false,
  });
  expect(toggle().props.accessibilityState.checked).toBe(false);
  expect(
    tree.root.findByType(DebugSettingsModal).props.initialSettings,
  ).toEqual(saved);
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Smoothing strength' }),
  ).toHaveLength(0);
});

test('live Kalman checkbox waits for native acknowledgement and suppresses repeated presses while saving', async () => {
  let acknowledge!: (settings: typeof DEFAULT_DEBUG_SETTINGS) => void;
  engine.setDebugSettings.mockImplementation(
    () =>
      new Promise(resolve => {
        acknowledge = resolve;
      }),
  );
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  const press = toggle().props.onPress;
  await act(async () => {
    press();
    press();
  });
  expect(engine.setDebugSettings).toHaveBeenCalledTimes(1);
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    kalmanFilterEnabled: true,
  });
  expect(toggle().props.disabled).toBe(true);
  expect(toggle().props.accessibilityState.disabled).toBe(true);
  expect(toggle().props.accessibilityState.checked).toBe(false);
  await act(async () => toggle().props.onPress());
  expect(engine.setDebugSettings).toHaveBeenCalledTimes(1);
  await act(async () =>
    acknowledge({ ...DEFAULT_DEBUG_SETTINGS, kalmanFilterEnabled: true }),
  );
  expect(toggle().props.disabled).toBe(false);
  expect(toggle().props.accessibilityState.disabled).toBe(false);
  expect(toggle().props.accessibilityState.checked).toBe(true);
});

test('live Kalman checkbox displays the acknowledged native value when it differs from the requested value', async () => {
  engine.setDebugSettings.mockResolvedValue({
    ...DEFAULT_DEBUG_SETTINGS,
    kalmanFilterEnabled: false,
    kalmanFilterSamples: 30,
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  await act(async () => toggle().props.onPress());
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    kalmanFilterEnabled: true,
  });
  expect(toggle().props.accessibilityState.checked).toBe(false);
  expect(toggle().props.disabled).toBe(false);
  expect(
    tree.root.findByType(DebugSettingsModal).props.initialSettings
      .kalmanFilterSamples,
  ).toBe(30);
});

test('failed live Kalman changes show the native error and preserve the last acknowledged setting', async () => {
  const status = await engine.getStatus();
  engine.getStatus.mockResolvedValue({
    ...status,
    aprilTag: {
      debugSettings: {
        ...DEFAULT_DEBUG_SETTINGS,
        kalmanFilterEnabled: true,
        kalmanFilterSamples: 10,
      },
    },
  });
  engine.setDebugSettings.mockRejectedValue(
    new Error('Filter settings unavailable'),
  );
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  expect(toggle().props.accessibilityState.checked).toBe(true);
  await act(async () => toggle().props.onPress());
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    kalmanFilterEnabled: false,
  });
  expect(alert).toHaveBeenCalledWith(
    expect.any(String),
    'Filter settings unavailable',
  );
  expect(toggle().props.accessibilityState.checked).toBe(true);
  expect(toggle().props.disabled).toBe(false);
});

test('live Kalman checkbox restores the native preference at startup and follows later native status changes', async () => {
  const status = await engine.getStatus();
  const saved = {
    ...DEFAULT_DEBUG_SETTINGS,
    kalmanFilterEnabled: true,
    kalmanFilterSamples: 20,
  };
  engine.getStatus.mockResolvedValue({
    ...status,
    aprilTag: { debugSettings: saved },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Kalman filter' });
  expect(toggle().props.accessibilityState.checked).toBe(true);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...status,
      aprilTag: { debugSettings: { ...saved, kalmanFilterEnabled: false } },
    });
  });
  expect(toggle().props.accessibilityState.checked).toBe(false);
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...status,
      aprilTag: { debugSettings: saved },
    });
  });
  expect(toggle().props.accessibilityState.checked).toBe(true);
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
});

test('distance delta threshold accepts zero and rejects invalid limits', () => {
  const draft = {
    tagSizeMeters: '165.1',
    maxDistanceMeters: '5',
    maxPlaneAngleDegrees: '60',
    warningDepthDifferenceMeters: '10',
    rejectDepthDifferenceMeters: '15',
    distanceDeltaThresholdMeters: '0',
    maxReprojectionErrorPixels: '3',
  };
  expect(parseDebugSettings(draft).distanceDeltaThresholdMeters).toBe(0);
  for (const value of ['', '-1', '1001', 'Infinity', 'NaN']) {
    expect(() =>
      parseDebugSettings({ ...draft, distanceDeltaThresholdMeters: value }),
    ).toThrow();
  }
});

test('AR width estimate requires explicit acceptance before changing tag size', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measure tag width with AR' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenCalledWith('tagWidth');
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
  expect(engine.applyMeasuredTagSize).not.toHaveBeenCalled();
  engine.getStatus.mockResolvedValue({
    recording: false,
    debugMode: false,
    measurement: { pointCount: 2, distanceMeters: 0.172 },
    spatial: { mode: 'tagWidth', floorSelected: true },
  });
  await act(async () => jest.advanceTimersByTime(2000));
  expect(JSON.stringify(tree.toJSON())).toContain('172.0 mm');
  expect(engine.applyMeasuredTagSize).not.toHaveBeenCalled();
  engine.applyMeasuredTagSize.mockResolvedValue({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.172,
    tagSizeSource: 'ar-two-point-edge',
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Use measured tag width' })
      .props.onPress(),
  );
  expect(engine.applyMeasuredTagSize).toHaveBeenCalledTimes(1);
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('distance');
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
});

test('threshold-only edits preserve the full precision of an AR-measured width', async () => {
  const measuredWidth = 0.1723456789;
  engine.getDebugSettings.mockResolvedValue({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: measuredWidth,
    tagSizeMode: 'custom',
    tagSizeSource: 'ar-two-point-edge',
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag width (mm)' }).props.value,
  ).toBe('172.3457');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Maximum 3D distance (m)' })
      .props.onChangeText('6'),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: measuredWidth,
    tagSizeMode: 'custom',
    maxDistanceMeters: 6,
  });
});

test('reset to automatic defaults replaces a measured width even when both display the same', async () => {
  engine.getDebugSettings.mockResolvedValue({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.16510000001,
    maxDistanceMeters: 6,
    tagSizeSource: 'ar-two-point-edge',
    showImperialHeight: false,
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag width (mm)' }).props.value,
  ).toBe('165.1');
  await act(async () =>
    tree.root
      .findByProps({
        accessibilityLabel: 'Reset debug settings to automatic defaults',
      })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith(DEFAULT_DEBUG_SETTINGS);
});

test('pose axes switch is opt-in and saves without rounding the measured tag width', async () => {
  const measuredWidth = 0.1723456789;
  engine.getDebugSettings.mockResolvedValue({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: measuredWidth,
    tagSizeMode: 'custom',
    tagSizeSource: 'ar-two-point-edge',
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  const toggle = tree.root.findByProps({
    accessibilityLabel: 'Show pose axes',
  });
  expect(toggle.props.value).toBe(false);
  await act(async () => toggle.props.onValueChange(true));
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: measuredWidth,
    tagSizeMode: 'custom',
    showPoseAxes: true,
  });
});

test('view zoom presets request native 1×, 2× and 4× and show acknowledged status', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(JSON.stringify(tree.toJSON())).toContain('View 1.0×');
  for (const zoom of [1, 2, 4]) {
    await act(async () =>
      tree.root
        .findByProps({ accessibilityLabel: `View zoom ${zoom}×` })
        .props.onPress(),
    );
    expect(engine.setDisplayZoom).toHaveBeenLastCalledWith(zoom);
    expect(JSON.stringify(tree.toJSON())).toContain(`View ${zoom.toFixed(1)}×`);
    expect(
      tree.root.findByProps({ accessibilityLabel: `View zoom ${zoom}×` }).props
        .accessibilityState.selected,
    ).toBe(true);
  }
});

test('view zoom waits for native acknowledgement instead of showing the requested preset optimistically', async () => {
  let acknowledge!: (value: { displayZoom: number }) => void;
  engine.setDisplayZoom.mockImplementation(
    () =>
      new Promise(resolve => {
        acknowledge = resolve;
      }),
  );
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'View zoom 2×' })
      .props.onPress();
  });
  expect(engine.setDisplayZoom).toHaveBeenCalledWith(2);
  expect(JSON.stringify(tree.toJSON())).toContain('View 1.0×');
  await act(async () => acknowledge({ displayZoom: 1.75 }));
  expect(JSON.stringify(tree.toJSON())).toContain('View 1.8×');
  expect(
    tree.root.findByProps({ accessibilityLabel: 'View zoom 2×' }).props
      .accessibilityState.selected,
  ).toBe(false);
});

test('native pinch status updates the continuous view zoom without issuing another preset request', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      recording: false,
      tracking: 'normal',
      lidarAvailable: true,
      depthAvailable: true,
      displayZoom: 2.6,
    });
  });
  expect(JSON.stringify(tree.toJSON())).toContain('View 2.6×');
  expect(engine.setDisplayZoom).not.toHaveBeenCalled();
  for (const zoom of [1, 2, 4]) {
    expect(
      tree.root.findByProps({ accessibilityLabel: `View zoom ${zoom}×` }).props
        .accessibilityState.selected,
    ).toBe(false);
  }
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', { displayZoom: 1 });
  });
  expect(JSON.stringify(tree.toJSON())).toContain('View 1.0×');
  expect(
    tree.root.findByProps({ accessibilityLabel: 'View zoom 1×' }).props
      .accessibilityState.selected,
  ).toBe(true);
});

test('a confirmed floor is reused for height mode and changing the floor enters setup', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Floor height measurement mode' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('height');
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Height is vertical above the selected floor',
  );
  expect(engine.completeFloorSetup).not.toHaveBeenCalled();
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Floor height measurement mode',
    }).props.accessibilityState.selected,
  ).toBe(true);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Select floor plane' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('selectFloor');
  expect(JSON.stringify(tree.toJSON())).toContain('SET UP THE FLOOR');
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      recording: false,
      tracking: 'normal',
      spatial: {
        mode: 'height',
        showFloorPlanes: true,
        floorSelected: true,
        floorId: 'test-floor',
        measurementCount: 2,
      },
      measurement: {
        kind: 'height',
        pointCount: 1,
        distanceMeters: 1.42,
        verticalMeters: 1.42,
      },
    });
  });
  const contents = JSON.stringify(tree.toJSON());
  expect(contents).toContain('2 measurements · floor set');
  expect(contents).toContain('142.0 cm (4 ft 7.9 in)');
  expect(contents).toContain('Height is vertical above the selected floor');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Two-point measurement mode' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('distance');
});

test('floor visibility follows the acknowledged native toggle state', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Toggle floor planes' }).props
      .accessibilityState.selected,
  ).toBe(false);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Toggle floor planes' })
      .props.onPress(),
  );
  expect(engine.setFloorVisible).toHaveBeenLastCalledWith(true);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Toggle floor planes' }).props
      .accessibilityState.selected,
  ).toBe(true);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Toggle floor planes' })
      .props.onPress(),
  );
  expect(engine.setFloorVisible).toHaveBeenLastCalledWith(false);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Toggle floor planes' }).props
      .accessibilityState.selected,
  ).toBe(false);
});

test('clear all measurements uses the explicit native action and retains the acknowledged floor reference', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    spatial: {
      mode: 'distance',
      showFloorPlanes: true,
      floorSelected: true,
      floorId: 'test-floor',
      measurementCount: 3,
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('3 measurements · floor set');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Clear all measurements' })
      .props.onPress(),
  );
  expect(engine.clearMeasurements).toHaveBeenCalledTimes(1);
  expect(JSON.stringify(tree.toJSON())).toContain('0 measurements · floor set');
});

test('tag-width entry, point reset and cancellation preserve completed measurement history', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    lidarAvailable: true,
    depthAvailable: true,
    spatial: {
      mode: 'distance',
      showFloorPlanes: true,
      floorSelected: true,
      floorId: 'test-floor',
      measurementCount: 3,
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measure tag width with AR' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('tagWidth');
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
  expect((await engine.getStatus()).spatial.measurementCount).toBe(3);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Reset tag width points' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('tagWidth');
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
  expect((await engine.getStatus()).spatial.measurementCount).toBe(3);
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Cancel tag width measurement' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenLastCalledWith('distance');
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
  expect((await engine.getStatus()).spatial.measurementCount).toBe(3);
});

test('saved height remains visible after pending points clear and is excluded from the tag-width prompt', async () => {
  const status = {
    recording: false,
    tracking: 'normal',
    lidarAvailable: true,
    depthAvailable: true,
    measurement: { pointCount: 0 },
    spatial: {
      mode: 'height',
      showFloorPlanes: true,
      floorSelected: true,
      floorId: 'test-floor',
      measurementCount: 1,
      lastMeasurement: {
        id: 'saved-height',
        kind: 'height',
        distanceMeters: 1.42,
        verticalMeters: 1.42,
      },
    },
  };
  engine.getStatus.mockResolvedValue(status);
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm (4 ft 7.9 in)');
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...status,
      recording: true,
      tracking: 'limited',
      measurement: { pointCount: 0 },
    });
  });
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm (4 ft 7.9 in)');
  await openDebugSettings();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measure tag width with AR' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('0 / 2 points');
  expect(JSON.stringify(tree.toJSON())).not.toContain('142.0 cm');
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
});

test('English height units default on for legacy settings, cancel locally, and persist only after Apply', async () => {
  const preciseWidth = 0.1723456789;
  const legacy = {
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: preciseWidth,
    tagSizeMode: 'custom' as const,
    tagSizeSource: 'ar-two-point-edge',
  };
  delete legacy.showImperialHeight;
  engine.getDebugSettings.mockResolvedValue(legacy);
  engine.setDebugSettings.mockImplementation(async (settings: unknown) => {
    engine.getDebugSettings.mockResolvedValue(settings);
    return settings;
  });
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    measurement: { kind: 'height', heightMeters: 1.42 },
    spatial: { mode: 'height', floorSelected: true },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm (4 ft 7.9 in)');
  await openDebugSettings();
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Show English units' });
  expect(toggle().props.value).toBe(true);
  await act(async () => toggle().props.onValueChange(false));
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
  await act(async () =>
    tree.root.findByType(DebugSettingsModal).props.onCancel(),
  );
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm (4 ft 7.9 in)');
  await openDebugSettings();
  expect(toggle().props.value).toBe(true);
  await act(async () => toggle().props.onValueChange(false));
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenLastCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: preciseWidth,
    tagSizeMode: 'custom' as const,
    showImperialHeight: false,
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm');
  expect(JSON.stringify(tree.toJSON())).not.toContain('4 ft 7.9 in');
  await openDebugSettings();
  expect(toggle().props.value).toBe(false);
});

test('native height-unit preference is reflected at startup without converting general distances', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    aprilTag: { debugSettings: { showImperialHeight: false } },
    measurement: { kind: 'height', heightMeters: 1.42 },
    spatial: { mode: 'height', floorSelected: true },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm');
  expect(JSON.stringify(tree.toJSON())).not.toContain('4 ft 7.9 in');
  await act(async () => {
    DeviceEventEmitter.emit('ARCaptureStatus', {
      recording: false,
      measurement: {
        kind: 'distance',
        pointCount: 2,
        distanceMeters: 1.42,
        verticalMeters: 0.5,
      },
    });
  });
  expect(JSON.stringify(tree.toJSON())).toContain('1.420 m');
  expect(JSON.stringify(tree.toJSON())).not.toContain('142.0 cm');
});

test('Measure scans first, gates Done on native readiness, and submits the displayed candidate ID', async () => {
  const scanning = {
    recording: false,
    tracking: 'normal',
    previewMode: 'camera',
    spatial: {
      mode: 'selectFloor',
      floorSelected: false,
      measurementCount: 0,
      floorSetup: {
        active: true,
        candidateSelected: false,
        ready: false,
        reason: 'floorNotSelected',
      },
    },
  };
  engine.getStatus.mockResolvedValue(scanning);
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measurement mode' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('SET UP THE FLOOR');
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Point at the floor and move slowly',
  );
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Two-point measurement mode',
    }),
  ).toHaveLength(0);
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Use measured tag width' }),
  ).toHaveLength(0);
  const done = () =>
    tree.root.findByProps({ accessibilityLabel: 'Finish floor setup' });
  expect(done().props.disabled).toBe(true);
  await act(async () => done().props.onPress());
  expect(engine.completeFloorSetup).not.toHaveBeenCalled();
  const candidate = {
    ...scanning,
    spatial: {
      ...scanning.spatial,
      floorSetup: {
        active: true,
        candidateSelected: true,
        candidateId: 'floor-to-review',
        areaSquareMeters: 0.999,
        minSpanMeters: 0.9,
        ready: false,
        reason: 'insufficientArea',
      },
    },
  };
  await act(async () => DeviceEventEmitter.emit('ARCaptureStatus', candidate));
  expect(JSON.stringify(tree.toJSON())).toContain('0.99 m² scanned');
  expect(done().props.disabled).toBe(true);
  for (const reason of ['trackingLimited', 'staleFrame']) {
    await act(async () =>
      DeviceEventEmitter.emit('ARCaptureStatus', {
        ...candidate,
        spatial: {
          ...candidate.spatial,
          floorSetup: {
            ...candidate.spatial.floorSetup,
            areaSquareMeters: 1.5,
            ready: false,
            reason,
          },
        },
      }),
    );
    expect(done().props.disabled).toBe(true);
  }
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...candidate,
      spatial: {
        ...candidate.spatial,
        floorSetup: {
          ...candidate.spatial.floorSetup,
          areaSquareMeters: 1.5,
          ready: true,
          reason: 'ready',
        },
      },
    }),
  );
  expect(done().props.disabled).toBe(false);
  engine.completeFloorSetup.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    spatial: {
      mode: 'height',
      floorSelected: true,
      floorId: 'floor-to-review',
      measurementCount: 0,
    },
  });
  await act(async () => done().props.onPress());
  expect(engine.completeFloorSetup).toHaveBeenCalledWith('floor-to-review');
  expect(JSON.stringify(tree.toJSON())).not.toContain('SET UP THE FLOOR');
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'Floor height measurement mode',
    }).props.accessibilityState.selected,
  ).toBe(true);
  expect(engine.applyMeasuredTagSize).not.toHaveBeenCalled();
});

test('AR-width entry scans before showing points and waits for Done acknowledgement', async () => {
  const scanning = {
    recording: false,
    tracking: 'normal',
    depthAvailable: true,
    previewMode: 'camera',
    measurement: { pointCount: 2, distanceMeters: 0.172 },
    spatial: {
      mode: 'selectFloor',
      floorSelected: false,
      measurementCount: 0,
      floorSetup: {
        active: true,
        candidateSelected: false,
        ready: false,
        reason: 'floorNotSelected',
      },
    },
  };
  engine.getStatus.mockResolvedValue(scanning);
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Measure tag width with AR' })
      .props.onPress(),
  );
  expect(engine.setSpatialMode).toHaveBeenCalledWith('tagWidth');
  expect(JSON.stringify(tree.toJSON())).toContain('SET UP THE FLOOR');
  expect(JSON.stringify(tree.toJSON())).not.toContain('MEASURE ONE TAG EDGE');
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Use measured tag width' }),
  ).toHaveLength(0);
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      ...scanning,
      spatial: {
        ...scanning.spatial,
        floorSetup: {
          active: true,
          candidateSelected: true,
          candidateId: 'width-floor',
          areaSquareMeters: 2,
          minSpanMeters: 1,
          ready: true,
          reason: 'ready',
        },
      },
    }),
  );
  let acknowledge!: (value: unknown) => void;
  engine.completeFloorSetup.mockImplementation(
    () =>
      new Promise(resolve => {
        acknowledge = resolve;
      }),
  );
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Finish floor setup' })
      .props.onPress();
  });
  expect(engine.completeFloorSetup).toHaveBeenCalledWith('width-floor');
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Finish floor setup' }).props
      .disabled,
  ).toBe(true);
  expect(JSON.stringify(tree.toJSON())).toContain('SET UP THE FLOOR');
  await act(async () =>
    acknowledge({
      recording: false,
      tracking: 'normal',
      previewMode: 'camera',
      measurement: { pointCount: 0 },
      spatial: {
        mode: 'tagWidth',
        floorSelected: true,
        floorId: 'width-floor',
        measurementCount: 0,
      },
    }),
  );
  expect(JSON.stringify(tree.toJSON())).not.toContain('SET UP THE FLOOR');
  expect(JSON.stringify(tree.toJSON())).toContain('MEASURE ONE TAG EDGE');
  expect(JSON.stringify(tree.toJSON())).toContain('0 / 2 points');
  expect(engine.applyMeasuredTagSize).not.toHaveBeenCalled();
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
});

test('floor leveling defaults off, saves explicitly and reloads the saved preference', async () => {
  engine.setDebugSettings.mockImplementation(async (settings: unknown) => {
    engine.getDebugSettings.mockResolvedValue(settings);
    return settings;
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await openDebugSettings();
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Level floor with gravity' });
  expect(toggle().props.value).toBe(false);
  await act(async () => toggle().props.onValueChange(true));
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    levelFloorWithGravity: true,
  });
  await openDebugSettings();
  expect(toggle().props.value).toBe(true);
  await act(async () => toggle().props.onValueChange(false));
  await act(async () =>
    tree.root.findByType(DebugSettingsModal).props.onCancel(),
  );
  await openDebugSettings();
  expect(toggle().props.value).toBe(true);
  expect(engine.setDebugSettings).toHaveBeenCalledTimes(1);
});

test('floor tilt readout preserves detected tilt while identifying a leveled measurement plane', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      spatial: {
        mode: 'distance',
        floorSelected: true,
        floorTiltDegrees: 2.36,
        levelFloorWithGravity: true,
      },
    }),
  );
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Floor tilt ≈2.4° · using level floor (0.0°)',
  );
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      spatial: {
        mode: 'selectFloor',
        floorSelected: false,
        floorTiltDegrees: 3.16,
        levelFloorWithGravity: true,
        floorSetup: { candidateSelected: true },
      },
    }),
  );
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Detected floor tilt ≈3.2° · level on Done',
  );
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      spatial: {
        mode: 'selectFloor',
        floorSelected: false,
        floorTiltDegrees: null,
        levelFloorWithGravity: true,
      },
    }),
  );
  expect(JSON.stringify(tree.toJSON())).not.toContain('Floor tilt');
  expect(JSON.stringify(tree.toJSON())).not.toContain('Detected floor tilt');
  await act(async () =>
    DeviceEventEmitter.emit('ARCaptureStatus', {
      spatial: {
        mode: 'distance',
        floorSelected: true,
        floorTiltDegrees: null,
      },
    }),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('Floor tilt unavailable');
  expect(JSON.stringify(tree.toJSON())).not.toContain('Floor tilt ≈0.0°');
});

test('live field status shows the current reason rather than a stale recorded warning', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    field: {
      packageId: 'frc-2026',
      label: 'FRC 2026',
      alignment: 'provisional',
      reason: 'Aligned from tag 5; position remains assumed.',
      warnings: ['An earlier tag had the wrong height.'],
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(
    tree.root.findByProps({
      accessibilityLabel:
        'Field alignment: provisional. Aligned from tag 5; position remains assumed.',
    }),
  ).toBeTruthy();
});
