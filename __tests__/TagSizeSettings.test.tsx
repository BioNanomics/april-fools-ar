import React from 'react';
import { Modal } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import {
  DebugSettingsModal,
  DEFAULT_DEBUG_SETTINGS,
  type DebugSettings,
} from '../DebugSettingsModal';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);

let tree: Renderer.ReactTestRenderer;
const onSave = jest.fn(async (_settings: DebugSettings) => {});
const onCancel = jest.fn();
const onMeasure = jest.fn();

const render = async (initialSettings = DEFAULT_DEBUG_SETTINGS) => {
  await act(async () => {
    tree = Renderer.create(
      <DebugSettingsModal
        visible
        initialSettings={initialSettings}
        onSave={onSave}
        onCancel={onCancel}
        onMeasure={onMeasure}
      />,
    );
  });
};

const press = async (accessibilityLabel: string) =>
  act(async () => {
    tree.root.findByProps({ accessibilityLabel }).props.onPress();
  });

afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
  jest.clearAllMocks();
});

test.each([
  ['Auto (LiDAR)', 'auto', 0.1651, 0],
  ['FTC', 'ftc', 0.08255, 2027],
  ['FRC', 'frc', 0.1651, 2026],
] as const)(
  '%s applies its exact native size and mode',
  async (label, mode, meters, competitionYear) => {
    await render({
      ...DEFAULT_DEBUG_SETTINGS,
      tagSizeMeters: 0.1723456789,
      tagSizeMode: 'custom',
      tagSizeSource: 'ar-two-point-edge',
    });
    await press(label);
    expect(onSave).not.toHaveBeenCalled();
    expect(
      tree.root.findByProps({ accessibilityLabel: label }).props
        .accessibilityState.checked,
    ).toBe(true);
    await press('Apply debug settings');
    expect(onSave).toHaveBeenCalledWith({
      ...DEFAULT_DEBUG_SETTINGS,
      tagSizeMode: mode,
      tagSizeMeters: meters,
      competitionYear,
    });
  },
);

test('a season width can be overridden with Custom while preserving thresholds', async () => {
  await render({ ...DEFAULT_DEBUG_SETTINGS, maxDistanceMeters: 7 });
  await press('FTC');
  await press('Custom width');
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Tag width (mm)' })
      .props.onChangeText('50.8');
  });
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Custom width' }).props
      .accessibilityState.checked,
  ).toBe(true);
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMode: 'custom',
    tagSizeMeters: 0.0508,
    maxDistanceMeters: 7,
  });
});

test('legacy measured settings keep their full precision and Custom mode', async () => {
  const legacy = {
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMeters: 0.08255000001,
    tagSizeSource: 'ar-two-point-edge',
  };
  delete legacy.tagSizeMode;
  await render(legacy);
  expect(
    tree.root.findByProps({ accessibilityLabel: 'Custom width' }).props
      .accessibilityState.checked,
  ).toBe(true);
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Maximum 3D distance (m)' })
      .props.onChangeText('8');
  });
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMode: 'custom',
    tagSizeMeters: legacy.tagSizeMeters,
    maxDistanceMeters: 8,
  });
});

test('a preset can be cancelled without persisting a setting', async () => {
  await render();
  await press('FTC');
  await act(async () => {
    tree.root.findByType(Modal).props.onRequestClose();
  });
  expect(onCancel).toHaveBeenCalledTimes(1);
  expect(onSave).not.toHaveBeenCalled();
});

test.each([
  ['FTC', 'FTC 2024 CENTERSTAGE', 2024, 0.0508],
  ['FTC', 'FTC 2025 INTO THE DEEP', 2025, 0.1016],
  ['FTC', 'FTC 2026 DECODE', 2026, 0.1651],
  ['FRC', 'FRC 2024 CRESCENDO', 2024, 0.1651],
  ['FRC', 'FRC 2025 REEFSCAPE', 2025, 0.1651],
] as const)(
  '%s season %s saves its year and reference size',
  async (fieldType, season, competitionYear, tagSizeMeters) => {
    await render();
    await press(fieldType);
    await press(season);
    expect(
      tree.root.findAllByProps({ accessibilityLabel: 'Tag width (mm)' }),
    ).toHaveLength(0);
    expect(
      tree.root.findByProps({ accessibilityLabel: season }).props
        .accessibilityState.checked,
    ).toBe(true);
    await press('Apply debug settings');
    expect(onSave).toHaveBeenCalledWith({
      ...DEFAULT_DEBUG_SETTINGS,
      tagSizeMode: fieldType.toLowerCase(),
      competitionYear,
      tagSizeMeters,
    });
  },
);

test('CENTERSTAGE describes both sizes and keeps reference width out of the form', async () => {
  await render();
  await press('FTC');
  await press('FTC 2024 CENTERSTAGE');
  const text = JSON.stringify(tree.toJSON());
  expect(text).toContain('2- and 5-inch tags');
  expect(text).toContain('Each tag ID uses its season size');
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Tag width (mm)' }),
  ).toHaveLength(0);
});

test('a saved year reopens selected and survives a threshold-only edit', async () => {
  await render({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMode: 'ftc',
    competitionYear: 2025,
    tagSizeMeters: 0.1016,
  });
  expect(
    tree.root.findByProps({
      accessibilityLabel: 'FTC 2025 INTO THE DEEP',
    }).props.accessibilityState.checked,
  ).toBe(true);
  await act(async () => {
    tree.root
      .findByProps({ accessibilityLabel: 'Maximum 3D distance (m)' })
      .props.onChangeText('9');
  });
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMode: 'ftc',
    competitionYear: 2025,
    tagSizeMeters: 0.1016,
    maxDistanceMeters: 9,
  });
});

test('Auto clears the selected field year and does not expose a reference width', async () => {
  await render({
    ...DEFAULT_DEBUG_SETTINGS,
    tagSizeMode: 'ftc',
    competitionYear: 2024,
    tagSizeMeters: 0.0508,
  });
  await press('Auto (LiDAR)');
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'FTC 2024 CENTERSTAGE' }),
  ).toHaveLength(0);
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Tag width (mm)' }),
  ).toHaveLength(0);
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(DEFAULT_DEBUG_SETTINGS);
});
