import React from 'react';
import { NativeModules, TextInput } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import App from '../App';

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

test('shows current native tag IDs before recording and clears absent tags', async () => {
  engine.getStatus.mockResolvedValue({
    recording: false,
    aprilTag: { state: 'running', family: 'tag36h11', ids: [4, 17] },
  });
  await act(async () => {
    tree = Renderer.create(<App />);
  });
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
