import React from 'react';
import { NativeModules, useWindowDimensions } from 'react-native';
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
let tree: Renderer.ReactTestRenderer;
const sizes = [
  { width: 852, height: 393 },
  { width: 834, height: 1210 },
  { width: 600, height: 1000 },
  { width: 1210, height: 834 },
  { width: 393, height: 852 },
];
const nativeCamera = () =>
  tree.root.find(
    node =>
      typeof node.type === 'string' && String(node.type) === 'ARCaptureView',
  ).parent!.instance;
const byLabel = (accessibilityLabel: string) =>
  tree.root.findByProps({ accessibilityLabel });
async function resize(width: number, height: number) {
  dimensions.mockReturnValue({ width, height, scale: 3, fontScale: 1 });
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
  engine.getDebugSettings.mockResolvedValue(DEFAULT_DEBUG_SETTINGS);
  engine.getStatus.mockResolvedValue({
    recording: false,
    tracking: 'normal',
    depthAvailable: true,
    displayZoom: 1,
    debugMode: true,
    spatial: { mode: 'distance', floorSelected: true, measurementCount: 0 },
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
  await act(async () =>
    byLabel('Session name').props.onChangeText('South field'),
  );
  await act(async () => byLabel('Session name').props.onFocus());
  for (const size of sizes) {
    await resize(size.width, size.height);
    expect(nativeCamera()).toBe(camera);
    expect(byLabel('Session name').props.value).toBe('South field');
    expect(byLabel('Start recording').props.onPress).toEqual(
      expect.any(Function),
    );
  }
  await act(async () => byLabel('Session name').props.onSubmitEditing());
  expect(nativeCamera()).toBe(camera);
  engine.startSession.mockResolvedValue(undefined);
  await act(async () => byLabel('Start recording').props.onPress());
  expect(engine.startSession).toHaveBeenCalledWith('South field');
  expect(engine.stopSession).not.toHaveBeenCalled();
  expect(engine.clearMeasurements).not.toHaveBeenCalled();
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
  for (const size of sizes) {
    await resize(size.width, size.height);
    expect(nativeCamera()).toBe(camera);
    expect(byLabel('Stop and save recording').props.onPress).toEqual(
      expect.any(Function),
    );
    expect(
      byLabel('Floor height measurement mode').props.accessibilityState
        .selected,
    ).toBe(true);
    expect(byLabel('View zoom 2×').props.accessibilityState.selected).toBe(
      true,
    );
    expect(
      tree.root.findAllByProps({ accessibilityLabel: 'Finish floor setup' }),
    ).toHaveLength(0);
  }
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
    await resize(size.width, size.height);
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
