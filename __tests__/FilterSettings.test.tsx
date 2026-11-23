import React from 'react';
import { StyleSheet, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import Renderer, { act } from 'react-test-renderer';
import {
  DebugSettings,
  DebugSettingsModal,
  DEFAULT_DEBUG_SETTINGS,
  KALMAN_FILTER_SAMPLE_OPTIONS,
} from '../DebugSettingsModal';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);
jest.mock('react-native/Libraries/Utilities/useWindowDimensions', () => ({
  __esModule: true,
  default: jest.fn(),
}));

let tree: Renderer.ReactTestRenderer;
let onSave: jest.Mock;
let onCancel: jest.Mock;
const byLabel = (accessibilityLabel: string) =>
  tree.root.findByProps({ accessibilityLabel });
const byTestID = (testID: string) => tree.root.findByProps({ testID });
const dimensions = jest.mocked(useWindowDimensions);
const safeArea = jest.mocked(useSafeAreaInsets);

function modal(initialSettings: DebugSettings, visible = true) {
  return (
    <DebugSettingsModal
      visible={visible}
      initialSettings={initialSettings}
      onSave={onSave}
      onCancel={onCancel}
      onMeasure={jest.fn()}
    />
  );
}

async function open(settings: DebugSettings = DEFAULT_DEBUG_SETTINGS) {
  await act(async () => {
    tree = Renderer.create(modal(settings));
  });
}

async function press(label: string) {
  await act(async () => byLabel(label).props.onPress());
}

beforeEach(() => {
  dimensions.mockReturnValue({
    width: 393,
    height: 852,
    scale: 3,
    fontScale: 1,
  });
  safeArea.mockReturnValue({ top: 0, right: 0, bottom: 0, left: 0 });
  onSave = jest.fn().mockResolvedValue(undefined);
  onCancel = jest.fn();
});

test('settings use a right-side landscape panel and preserve drafts through both landscape rotations', async () => {
  const settings = { ...DEFAULT_DEBUG_SETTINGS, kalmanFilterEnabled: true };
  await open(settings);
  await act(async () =>
    byLabel('Distance delta threshold (cm)').props.onChangeText('22'),
  );
  await press('Smoothing strength');
  await press('20 samples');
  const layouts = [
    {
      width: 874,
      height: 402,
      inset: { top: 0, right: 62, bottom: 21, left: 0 },
    },
    {
      width: 874,
      height: 402,
      inset: { top: 0, right: 0, bottom: 21, left: 62 },
    },
    {
      width: 568,
      height: 320,
      inset: { top: 0, right: 0, bottom: 0, left: 0 },
    },
    {
      width: 1210,
      height: 834,
      inset: { top: 24, right: 0, bottom: 20, left: 0 },
    },
    {
      width: 402,
      height: 874,
      inset: { top: 62, right: 0, bottom: 34, left: 0 },
    },
  ];
  for (const { width, height, inset } of layouts) {
    dimensions.mockReturnValue({ width, height, scale: 3, fontScale: 1 });
    safeArea.mockReturnValue(inset);
    await act(async () => tree.update(modal(settings)));
    const backdrop = StyleSheet.flatten(
      byTestID('debug.settings.backdrop').props.style,
    );
    const sheet = StyleSheet.flatten(
      byTestID('debug.settings.sheet').props.style,
    );
    const landscape = width > height;
    if (landscape) {
      expect(backdrop.alignItems).toBe('flex-end');
      expect(sheet.width).toBeLessThan(width / 2);
      expect(backdrop.paddingTop).toBeGreaterThanOrEqual(inset.top + 52);
      expect(sheet.maxHeight).toBeGreaterThan(height / 2);
    } else {
      expect(backdrop.alignItems).toBe('center');
      expect(backdrop.paddingTop).toBe(height / 2);
      expect(sheet.maxHeight).toBeLessThanOrEqual(height / 2);
    }
    expect(backdrop.paddingRight).toBeGreaterThanOrEqual(inset.right);
    expect(sheet.marginBottom).toBeGreaterThanOrEqual(inset.bottom);
    expect(
      backdrop.paddingTop + sheet.maxHeight + sheet.marginBottom,
    ).toBeLessThanOrEqual(height);
    const fields = byTestID('debug.settings.fields');
    const actions = byTestID('debug.settings.actions');
    expect(actions.parent).toBe(fields.parent);
    for (const label of ['Cancel debug settings', 'Apply debug settings']) {
      expect(
        StyleSheet.flatten(byLabel(label).props.style).minHeight,
      ).toBeGreaterThanOrEqual(44);
    }
    expect(byLabel('Distance delta threshold (cm)').props.value).toBe('22');
    expect(byLabel('Smoothing strength').props.accessibilityValue.text).toBe(
      '20 samples',
    );
  }
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(
    expect.objectContaining({
      distanceDeltaThresholdMeters: 0.22,
      kalmanFilterSamples: 20,
    }),
  );
});

afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
});

test('older saved settings open with filtering off and the sample selector disabled', async () => {
  const oldSettings = { ...DEFAULT_DEBUG_SETTINGS };
  delete oldSettings.kalmanFilterEnabled;
  delete oldSettings.kalmanFilterSamples;
  await open(oldSettings);
  expect(byLabel('Kalman filter').props.accessibilityRole).toBe('checkbox');
  expect(byLabel('Kalman filter').props.accessibilityState.checked).toBe(false);
  expect(byLabel('Smoothing strength').props.disabled).toBe(true);
  expect(byLabel('Smoothing strength').props.accessibilityValue.text).toBe(
    '5 samples',
  );
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(
    expect.objectContaining({
      kalmanFilterEnabled: false,
      kalmanFilterSamples: 5,
    }),
  );
});

test('enabling the filter exposes sample choices and saves the selected strength', async () => {
  await open();
  await press('Kalman filter');
  expect(byLabel('Kalman filter').props.accessibilityState.checked).toBe(true);
  expect(byLabel('Smoothing strength').props.disabled).toBe(false);
  await press('Smoothing strength');
  expect(byLabel('Smoothing strength').props.accessibilityState.expanded).toBe(
    true,
  );
  const options = tree.root.findAllByProps({ accessibilityRole: 'radio' });
  expect([
    ...new Set(options.map(option => option.props.accessibilityLabel)),
  ]).toEqual(KALMAN_FILTER_SAMPLE_OPTIONS.map(samples => `${samples} samples`));
  expect(byLabel('5 samples').props.accessibilityState.checked).toBe(true);
  await press('20 samples');
  expect(byLabel('Smoothing strength').props.accessibilityValue.text).toBe(
    '20 samples',
  );
  expect(byLabel('Smoothing strength').props.accessibilityState.expanded).toBe(
    false,
  );
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(
    expect.objectContaining({
      kalmanFilterEnabled: true,
      kalmanFilterSamples: 20,
    }),
  );
});

test('turning filtering off closes the choices and preserves its selected strength', async () => {
  await open({
    ...DEFAULT_DEBUG_SETTINGS,
    kalmanFilterEnabled: true,
    kalmanFilterSamples: 30,
  });
  await press('Smoothing strength');
  await press('Kalman filter');
  expect(byLabel('Smoothing strength').props.disabled).toBe(true);
  expect(tree.root.findAllByProps({ accessibilityRole: 'radio' })).toHaveLength(
    0,
  );
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(
    expect.objectContaining({
      kalmanFilterEnabled: false,
      kalmanFilterSamples: 30,
    }),
  );
  await press('Kalman filter');
  await press('Smoothing strength');
  expect(byLabel('30 samples').props.accessibilityState.checked).toBe(true);
});

test('reset restores filtering defaults along with the other settings', async () => {
  await open({
    ...DEFAULT_DEBUG_SETTINGS,
    kalmanFilterEnabled: true,
    kalmanFilterSamples: 20,
  });
  await press('Smoothing strength');
  await press('Reset debug settings to FRC defaults');
  expect(byLabel('Kalman filter').props.accessibilityState.checked).toBe(false);
  expect(byLabel('Smoothing strength').props.disabled).toBe(true);
  expect(byLabel('Smoothing strength').props.accessibilityValue.text).toBe(
    '5 samples',
  );
  expect(tree.root.findAllByProps({ accessibilityRole: 'radio' })).toHaveLength(
    0,
  );
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(DEFAULT_DEBUG_SETTINGS);
});

test('cancel and reopen discard unsaved filtering changes', async () => {
  const saved = {
    ...DEFAULT_DEBUG_SETTINGS,
    kalmanFilterEnabled: true,
    kalmanFilterSamples: 10,
  };
  await open(saved);
  await press('Smoothing strength');
  await press('30 samples');
  await press('Kalman filter');
  await act(async () => {
    tree.root.findByType(DebugSettingsModal).props.onCancel();
    tree.update(modal(saved, false));
  });
  expect(onCancel).toHaveBeenCalledTimes(1);
  expect(onSave).not.toHaveBeenCalled();
  await act(async () => tree.update(modal(saved)));
  expect(byLabel('Kalman filter').props.accessibilityState.checked).toBe(true);
  expect(byLabel('Smoothing strength').props.accessibilityValue.text).toBe(
    '10 samples',
  );
});

test('saving disables filtering controls until native settings finish applying', async () => {
  let finishSave!: () => void;
  onSave.mockImplementation(
    () =>
      new Promise<void>(resolve => {
        finishSave = resolve;
      }),
  );
  await open({ ...DEFAULT_DEBUG_SETTINGS, kalmanFilterEnabled: true });
  let saveResult: Promise<void>;
  await act(async () => {
    saveResult = byLabel('Apply debug settings').props.onPress();
  });
  expect(byLabel('Kalman filter').props.disabled).toBe(true);
  expect(byLabel('Smoothing strength').props.disabled).toBe(true);
  await act(async () => {
    finishSave();
    await saveResult;
  });
  expect(byLabel('Kalman filter').props.disabled).toBe(false);
  expect(byLabel('Smoothing strength').props.disabled).toBe(false);
});
