import React from 'react';
import { NativeModules, TextInput } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import App from '../App';
import { DEFAULT_DEBUG_SETTINGS } from '../DebugSettingsModal';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);
jest.mock('react-native', () => {
  const native = jest.requireActual('react-native');
  native.NativeModules.ARCaptureEngine = {
    getStatus: jest.fn(),
    startSession: jest.fn(),
    stopSession: jest.fn(),
    listSessions: jest.fn().mockResolvedValue([]),
    clearMeasurements: jest.fn(),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
    setPreviewMode: jest.fn().mockResolvedValue(undefined),
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
  });
  engine.setDebugMode.mockImplementation(async (enabled: boolean) => ({
    ...(await engine.getStatus()),
    debugMode: enabled,
  }));
  engine.getDebugSettings.mockResolvedValue(DEFAULT_DEBUG_SETTINGS);
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
  expect(engine.clearMeasurements).toHaveBeenCalledTimes(1);
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
