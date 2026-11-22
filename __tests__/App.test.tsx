import React from 'react';
import { DeviceEventEmitter, NativeModules, TextInput } from 'react-native';
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
jest.mock('react-native', () => {
  const native = jest.requireActual('react-native');
  native.NativeModules.ARCaptureEngine = {
    getStatus: jest.fn(),
    getAppInfo: jest.fn(),
    startSession: jest.fn(),
    stopSession: jest.fn(),
    listSessions: jest.fn().mockResolvedValue([]),
    clearMeasurements: jest.fn(),
    setSpatialMode: jest.fn(),
    setFloorVisible: jest.fn(),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
    setPreviewMode: jest.fn().mockResolvedValue(undefined),
    setDisplayZoom: jest.fn(),
    setDebugMode: jest.fn(),
    getDebugSettings: jest.fn(),
    setDebugSettings: jest.fn(),
    applyMeasuredTagSize: jest.fn(),
  };
  return native;
});

const engine = NativeModules.ARCaptureEngine;
let tree: Renderer.ReactTestRenderer;
beforeEach(() => {
  jest.useFakeTimers();
  jest.clearAllMocks();
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    lidarAvailable: true,
    depthAvailable: true,
    displayZoom: 1,
    spatial: {
      mode: 'distance',
      showFloorPlanes: false,
      floorSelected: false,
      measurementCount: 0,
    },
  });
  engine.setDebugMode.mockImplementation(async (enabled: boolean) => ({
    ...(await engine.getStatus()),
    debugMode: enabled,
  }));
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
          mode === 'height' && !status.spatial?.floorSelected
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
    bundleId: 'com.doughorner.aprilfoolsar',
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
});

test('starts a named native recording and stops it using the same control', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root.findByType(TextInput).props.onChangeText('North field'),
  );
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

test('shows the native installed version and opens its build information', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  expect(JSON.stringify(tree.toJSON())).toContain('v0.1.1 (6) · 1234567');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Version and release notes' })
      .props.onPress(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain(
    '1234567890abcdef1234567890abcdef12345678',
  );
  expect(JSON.stringify(tree.toJSON())).toContain('2026-11-21T10:00:00Z');
  expect(engine.startSession).not.toHaveBeenCalled();
});

test('falls back to a nonempty session name when the input is blank', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root.findByType(TextInput).props.onChangeText('  '),
  );
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
  });
  await act(async () => jest.advanceTimersByTime(2000));
  expect(JSON.stringify(tree.toJSON())).toContain('Looking for tags');
  expect(JSON.stringify(tree.toJSON())).not.toContain('Visible: #4, #17');
});

test('debug settings convert displayed millimeters and centimeters to native meters', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
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
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Apply debug settings' })
      .props.onPress(),
  );
  expect(engine.setDebugSettings).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.2,
    warningDepthDifferenceMeters: 0.08,
    rejectDepthDifferenceMeters: 0.12,
  });
});

test('AR width estimate requires explicit acceptance before changing tag size', async () => {
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
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
    tagSizeSource: 'ar-two-point-edge',
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag width (mm)' }).props.value,
  ).toBe('172.3457');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Maximum range (m)' })
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
    maxDistanceMeters: 6,
  });
});

test('reset to FRC defaults replaces a measured width even when both display the same', async () => {
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
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Tag width (mm)' }).props.value,
  ).toBe('165.1');
  await act(async () =>
    tree.root
      .findByProps({
        accessibilityLabel: 'Reset debug settings to FRC defaults',
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
    tagSizeSource: 'ar-two-point-edge',
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
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

test('measurement modes request the native workflow and confirmed-floor status updates the displayed height', async () => {
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
  expect(JSON.stringify(tree.toJSON())).toContain('tap the highlighted floor');
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
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
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
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
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
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
  const toggle = () =>
    tree.root.findByProps({ accessibilityLabel: 'Show English units' });
  expect(toggle().props.value).toBe(true);
  await act(async () => toggle().props.onValueChange(false));
  expect(engine.setDebugSettings).not.toHaveBeenCalled();
  await act(async () =>
    tree.root.findByType(DebugSettingsModal).props.onCancel(),
  );
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm (4 ft 7.9 in)');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
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
    showImperialHeight: false,
  });
  expect(JSON.stringify(tree.toJSON())).toContain('142.0 cm');
  expect(JSON.stringify(tree.toJSON())).not.toContain('4 ft 7.9 in');
  await act(async () =>
    tree.root
      .findByProps({ accessibilityLabel: 'Debug settings' })
      .props.onPress(),
  );
  expect(toggle().props.value).toBe(false);
});

test('native height-unit preference is reflected at startup without converting general distances', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    aprilTag: { debugSettings: { showImperialHeight: false } },
    measurement: { kind: 'height', heightMeters: 1.42 },
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
