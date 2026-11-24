import React from 'react';
import {
  FlatList,
  NativeModules,
  ScrollView,
  StyleSheet,
  useWindowDimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Renderer, { act } from 'react-test-renderer';
import App from '../App';
import {
  DebugSettingsModal,
  DEFAULT_DEBUG_SETTINGS,
} from '../DebugSettingsModal';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);
jest.mock('react-native/Libraries/Utilities/useWindowDimensions', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('react-native', () => {
  const native = jest.requireActual('react-native');
  native.NativeModules.ARCaptureEngine = {
    getStatus: jest.fn(),
    getAppInfo: jest.fn().mockResolvedValue(null),
    getDebugSettings: jest.fn(),
    setDebugSettings: jest.fn(),
    startSession: jest.fn(),
    stopSession: jest.fn(),
    setDebugMode: jest.fn(),
    setPreviewMode: jest.fn().mockResolvedValue(undefined),
    setDisplayZoom: jest.fn(),
    setSpatialMode: jest.fn(),
    clearMeasurements: jest.fn(),
    completeFloorSetup: jest.fn(),
    listSessions: jest.fn().mockResolvedValue([]),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
  };
  return native;
});

const engine = NativeModules.ARCaptureEngine;
const dimensions = jest.mocked(useWindowDimensions);
const safeAreaInsets = jest.mocked(useSafeAreaInsets);
let tree: Renderer.ReactTestRenderer;
const sizes = [
  { width: 852, height: 393 },
  { width: 852, height: 393, notchRight: true },
  { width: 834, height: 1210 },
  { width: 600, height: 1000 },
  { width: 1210, height: 834 },
  { width: 393, height: 852 },
  { width: 740, height: 360 },
  { width: 393, height: 852 },
];
function insetsFor(width: number, height: number, notchRight = false) {
  if (width > height) {
    return {
      top: 0,
      bottom: 21,
      left: notchRight ? 0 : 62,
      right: notchRight ? 62 : 0,
    };
  }
  return { top: 62, bottom: 34, left: 0, right: 0 };
}
const nativeCamera = () =>
  tree.root.find(
    node =>
      typeof node.type === 'string' && String(node.type) === 'ARCaptureView',
  ).parent!.instance;
const byLabel = (accessibilityLabel: string) =>
  tree.root.findByProps({ accessibilityLabel });
const byTestID = (testID: string) => tree.root.findByProps({ testID });
function expectWithin(
  node: Renderer.ReactTestInstance,
  ancestor: Renderer.ReactTestInstance,
) {
  let current: Renderer.ReactTestInstance | null = node;
  while (current && current !== ancestor) {
    current = current.parent;
  }
  expect(current).toBe(ancestor);
}
function expectDockPlacement(width: number, height: number) {
  const dock = StyleSheet.flatten(byTestID('capture.thumbDock').props.style);
  const inset = safeAreaInsets.mock.results.at(-1)!.value;
  expect(dock.position).toBe('absolute');
  if (width > height) {
    const badge = StyleSheet.flatten(byTestID('app.versionBadge').props.style);
    expect(dock.right).toBeGreaterThanOrEqual(inset.right);
    expect(typeof dock.width).toBe('number');
    expect(dock.width).toBeLessThanOrEqual(width / 2);
    expect(dock.width).toBeGreaterThanOrEqual(240);
    expect(dock.top).toBeGreaterThanOrEqual(badge.top + badge.minHeight);
    expect(dock.bottom).toBeGreaterThanOrEqual(inset.bottom);
    // Landscape gains vertical room while leaving most of the camera width clear.
    const dockHeight = dock.height ?? dock.maxHeight;
    expect(dockHeight).toBeGreaterThan(height / 2);
    expect(dock.top + dockHeight + dock.bottom).toBeLessThanOrEqual(height);
    expect(dock.right + dock.width).toBeLessThanOrEqual(width - inset.left);
  } else {
    expect(dock.bottom).toBeGreaterThanOrEqual(0);
    expect(dock.top).toBeUndefined();
    expect(dock.maxHeight).toBeLessThanOrEqual(height / 2);
    expect(dock.bottom + dock.paddingBottom).toBeGreaterThanOrEqual(
      inset.bottom,
    );
  }
}
async function resize(width: number, height: number, notchRight = false) {
  dimensions.mockReturnValue({ width, height, scale: 3, fontScale: 1 });
  safeAreaInsets.mockReturnValue(insetsFor(width, height, notchRight));
  await act(async () => tree.update(<App />));
}

beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  dimensions.mockReturnValue({
    width: 393,
    height: 852,
    scale: 3,
    fontScale: 1,
  });
  safeAreaInsets.mockReturnValue(insetsFor(393, 852));
  engine.getDebugSettings.mockResolvedValue(DEFAULT_DEBUG_SETTINGS);
  engine.listSessions.mockResolvedValue([]);
  engine.getAppInfo.mockResolvedValue({
    bundleId: 'com.bionanomics.aprilfoolsar',
    version: '0.1.1',
    build: '6',
    buildCommit: '1234567890abcdef1234567890abcdef12345678',
    buildDateUTC: '2026-11-21T10:00:00Z',
    workingTreeDirty: false,
    releaseNotes: [],
  });
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    depthAvailable: true,
    displayZoom: 1,
    debugMode: true,
    spatial: { mode: 'distance', floorSelected: true, measurementCount: 0 },
  });
  engine.setDebugMode.mockImplementation(async (debugMode: boolean) => {
    const next = { ...(await engine.getStatus()), debugMode };
    engine.getStatus.mockResolvedValue(next);
    return next;
  });
});
afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
  jest.useRealTimers();
});

test('resizing preserves the native camera and entered recording name across phone and tablet layouts', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  expect(camera).toBeTruthy();
  await act(async () => byLabel('Edit session name').props.onPress());
  await act(async () =>
    byLabel('Session name').props.onChangeText('South field'),
  );
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expect(nativeCamera()).toBe(camera);
    expect(byLabel('Session name').props.value).toBe('South field');
    expect(byLabel('Start recording').props.onPress).toEqual(
      expect.any(Function),
    );
    expectWithin(byLabel('Session name'), byTestID('capture.toolSheet'));
    expectWithin(byLabel('Start recording'), byTestID('capture.thumbDock'));
    expectDockPlacement(size.width, size.height);
  }
  await act(async () => byLabel('Close capture tools').props.onPress());
  expect(nativeCamera()).toBe(camera);
  engine.startSession.mockResolvedValue(undefined);
  await act(async () => byLabel('Start recording').props.onPress());
  expect(engine.startSession).toHaveBeenCalledWith('South field');
  expect(engine.stopSession).not.toHaveBeenCalled();
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
});

test('tag details follows the orientation-specific tool panel while recording stays reachable', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  await act(async () => byLabel('Tag details').props.onPress());
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expectWithin(byTestID('capture.tagReadout'), byTestID('capture.toolSheet'));
    expectWithin(byTestID('capture.toolSheet'), byTestID('capture.thumbDock'));
    expectWithin(
      byLabel('Start recording'),
      byTestID('capture.recordingControls'),
    );
    expectDockPlacement(size.width, size.height);
    expect(nativeCamera()).toBe(camera);
  }
  await act(async () => byLabel('Close capture tools').props.onPress());
  expect(
    tree.root.findAllByProps({ testID: 'capture.tagReadout' }),
  ).toHaveLength(0);
  expect(byLabel('Kalman filter').props.onPress).toEqual(expect.any(Function));
  expect(nativeCamera()).toBe(camera);
});

test('primary actions use a right-side landscape dock and a lower-half portrait dock across phone and tablet layouts', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    const dock = byTestID('capture.thumbDock');
    expectDockPlacement(size.width, size.height);
    expectWithin(byTestID('capture.navigation'), dock);
    expectWithin(byTestID('capture.quickControls'), dock);
    expectWithin(byTestID('capture.recordingControls'), dock);
    for (const label of [
      'Saved sessions',
      'Tag debug mode',
      'Measurement mode',
      'Debug settings',
      'Kalman filter',
      'Tag details',
      'View zoom 1×',
      'View zoom 2×',
      'View zoom 4×',
      'More controls',
      'Start recording',
    ]) {
      expectWithin(byLabel(label), dock);
      expect(byLabel(label).props.onPress).toEqual(expect.any(Function));
    }
    const accessibleActions = tree.root.findAll(
      node =>
        ['button', 'checkbox', 'tab'].includes(node.props.accessibilityRole) &&
        typeof node.props.onPress === 'function' &&
        node.props.accessibilityLabel !== 'Open version and release notes',
    );
    for (const action of accessibleActions) {
      expectWithin(action, dock);
    }
    expect(byLabel('Tag debug mode').props.accessibilityRole).toBe('tab');
    expect(byLabel('Tag debug mode').props.accessibilityState.selected).toBe(
      true,
    );
    expect(byLabel('Measurement mode').props.accessibilityRole).toBe('tab');
    expect(byLabel('Saved sessions').props.accessibilityRole).toBe('tab');
    expect(nativeCamera()).toBe(camera);
  }
});

test('More and Saved use the same orientation-specific side or bottom panel', async () => {
  engine.listSessions.mockResolvedValue([
    {
      id: 'south-field',
      name: 'South field',
      createdAt: '2026-11-23T05:00:00Z',
      durationSeconds: 60,
      sizeBytes: 2048,
      finalized: true,
    },
  ]);
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  await act(async () => byLabel('More controls').props.onPress());
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expectDockPlacement(size.width, size.height);
    const tools = byTestID('capture.toolSheet');
    expectWithin(byLabel('About and sponsors'), tools.findByType(ScrollView));
    expectWithin(byLabel('Version and release notes'), tools);
    expectWithin(
      byLabel('Start recording'),
      byTestID('capture.recordingControls'),
    );
    expect(
      tools.findAllByProps({ testID: 'capture.recordingControls' }),
    ).toHaveLength(0);
    expect(nativeCamera()).toBe(camera);
  }
  await act(async () => byLabel('Close capture tools').props.onPress());
  await act(async () => byLabel('Saved sessions').props.onPress());
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expectDockPlacement(size.width, size.height);
    const dock = byTestID('capture.thumbDock');
    expect(byLabel('Saved sessions').props.accessibilityState.selected).toBe(
      true,
    );
    expectWithin(byLabel('Refresh saved sessions'), dock);
    expectWithin(byLabel('Play recording South field'), dock);
    expectWithin(byLabel('Share recording South field'), dock);
    // A side panel must not retain a tablet's two-column list when rotated.
    if (size.width > size.height) {
      expect(dock.findByType(FlatList).props.numColumns).toBe(1);
    }
  }
  expect(engine.startSession).not.toHaveBeenCalled();
  expect(engine.stopSession).not.toHaveBeenCalled();
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
});

test('installed version remains in the upper right across phone and tablet layouts', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    const badge = byTestID('app.versionBadge');
    const badgeStyle = StyleSheet.flatten(badge.props.style);
    expect(badgeStyle.position).toBe('absolute');
    expect(badgeStyle.top).toBeGreaterThanOrEqual(0);
    expect(badgeStyle.right).toBeGreaterThanOrEqual(0);
    expect(badgeStyle.bottom).toBeUndefined();
    expect(badgeStyle.left).toBeUndefined();
    expect(badgeStyle.minHeight).toBeGreaterThanOrEqual(44);
    expect(badge.props.accessibilityRole).toBe('button');
    expect(badge.props.accessibilityLabel).toBe(
      'Open version and release notes',
    );
    expect(badge.props.onPress).toEqual(expect.any(Function));
    expect(
      badge.findByProps({ accessibilityLabel: 'Installed app version' }).props
        .children,
    ).toBe('v0.1.1 (6)');
  }
});

test('resizing an active recording preserves its native camera, selected floor and height tool', async () => {
  engine.getStatus.mockResolvedValue({
    recording: true,
    tracking: 'normal',
    depthAvailable: true,
    displayZoom: 2,
    debugMode: false,
    spatial: {
      mode: 'height',
      floorSelected: true,
      floorId: 'selected-floor',
      measurementCount: 2,
      lastMeasurement: { kind: 'height', heightMeters: 1.2, pointCount: 1 },
    },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  if (tree.root.findAllByProps({ testID: 'capture.toolSheet' }).length === 0) {
    await act(async () => byLabel('Measurement mode').props.onPress());
  }
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expect(nativeCamera()).toBe(camera);
    expect(byLabel('Stop and save recording').props.onPress).toEqual(
      expect.any(Function),
    );
    expect(
      byLabel('Floor height measurement mode').props.accessibilityState
        .selected,
    ).toBe(true);
    expectWithin(
      byLabel('Floor height measurement mode'),
      byTestID('capture.toolSheet'),
    );
    expectWithin(
      byLabel('Stop and save recording'),
      byTestID('capture.recordingControls'),
    );
    expect(
      tree.root.findAllByProps({ accessibilityLabel: 'Finish floor setup' }),
    ).toHaveLength(0);
    expectDockPlacement(size.width, size.height);
    const scrollingTools = byTestID('capture.toolSheet').findByType(ScrollView);
    expectWithin(byLabel('Floor height measurement mode'), scrollingTools);
    expect(
      scrollingTools.findAllByProps({ testID: 'capture.recordingControls' }),
    ).toHaveLength(0);
  }
  await act(async () => byLabel('Close capture tools').props.onPress());
  expect(byLabel('View zoom 2×').props.accessibilityState.selected).toBe(true);
  expect(engine.startSession).not.toHaveBeenCalled();
  expect(engine.stopSession).not.toHaveBeenCalled();
  expect(engine.setSpatialMode).not.toHaveBeenCalled();
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
});

test('resizing keeps an unsaved settings draft and cancel leaves native settings unchanged', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  const camera = nativeCamera();
  await act(async () => byLabel('Debug settings').props.onPress());
  await act(async () =>
    byLabel('Distance delta threshold (cm)').props.onChangeText('22'),
  );
  for (const size of sizes) {
    await resize(size.width, size.height, size.notchRight);
    expect(nativeCamera()).toBe(camera);
    expect(byLabel('Distance delta threshold (cm)').props.value).toBe('22');
  }
  await act(async () =>
    tree.root.findByType(DebugSettingsModal).props.onCancel(),
  );
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Distance delta threshold (cm)',
    }),
  ).toHaveLength(0);
});
