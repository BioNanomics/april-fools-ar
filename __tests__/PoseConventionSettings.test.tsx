import React from 'react';
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
const modal = (initialSettings: DebugSettings, visible = true) => (
  <DebugSettingsModal
    visible={visible}
    initialSettings={initialSettings}
    onSave={onSave}
    onCancel={onCancel}
    onMeasure={onMeasure}
  />
);
const render = async (settings: DebugSettings = DEFAULT_DEBUG_SETTINGS) => {
  await act(async () => {
    tree = Renderer.create(modal(settings));
  });
};
const byLabel = (label: string) =>
  tree.root.findByProps({ accessibilityLabel: label });
const press = async (label: string) =>
  act(async () => byLabel(label).props.onPress());

afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
  jest.clearAllMocks();
});

test('legacy settings default to FRC pose coordinates in a separate accessible group', async () => {
  const legacy = { ...DEFAULT_DEBUG_SETTINGS };
  delete legacy.poseConvention;
  await render(legacy);
  const group = byLabel('Pose coordinates');
  expect(group.props.accessibilityRole).toBe('radiogroup');
  const choices = group.findAllByProps({ accessibilityRole: 'radio' });
  const labels = [
    ...new Set(choices.map(option => option.props.accessibilityLabel)),
  ];
  expect(labels).toEqual(['Raw optical', 'FTC SDK', 'FRC / PhotonVision']);
  expect(
    labels.filter(label => byLabel(label).props.accessibilityState.checked),
  ).toHaveLength(1);
  expect(byLabel('FRC / PhotonVision').props.accessibilityState.checked).toBe(
    true,
  );
  expect(JSON.stringify(tree.toJSON())).toContain(
    'Camera axes: +X forward, +Y left, +Z up.',
  );
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(DEFAULT_DEBUG_SETTINGS);
});

test.each([
  ['Raw optical', 'rawOptical', '+X right, +Y down, +Z forward'],
  ['FTC SDK', 'ftcSdk', '+X right, +Y forward, +Z up'],
  ['FRC / PhotonVision', 'frcPhotonVision', '+X forward, +Y left, +Z up'],
] as const)(
  '%s saves its pose convention without changing the selected tag-size season',
  async (label, poseConvention, axes) => {
    const initial: DebugSettings = {
      ...DEFAULT_DEBUG_SETTINGS,
      tagSizeMode: 'ftc',
      competitionYear: 2024,
      tagSizeMeters: 0.0508,
      maxDistanceMeters: 7,
    };
    await render(initial);
    await press(label);
    expect(onSave).not.toHaveBeenCalled();
    expect(byLabel(label).props.accessibilityState.checked).toBe(true);
    expect(JSON.stringify(tree.toJSON())).toContain(axes);
    expect(
      byLabel('FTC 2024 CENTERSTAGE').props.accessibilityState.checked,
    ).toBe(true);
    await press('Apply debug settings');
    expect(onSave).toHaveBeenCalledWith({ ...initial, poseConvention });
  },
);

test.each(['Auto (LiDAR)', 'FTC', 'FRC', 'Custom width'])(
  'selecting %s for tag size preserves the independent FTC pose convention',
  async sizeLabel => {
    await render({ ...DEFAULT_DEBUG_SETTINGS, poseConvention: 'ftcSdk' });
    await press(sizeLabel);
    expect(byLabel('FTC SDK').props.accessibilityState.checked).toBe(true);
    await press('Apply debug settings');
    expect(onSave).toHaveBeenCalledWith(
      expect.objectContaining({ poseConvention: 'ftcSdk' }),
    );
  },
);

test('cancel discards a pose draft and reopening restores the saved convention', async () => {
  const initial: DebugSettings = {
    ...DEFAULT_DEBUG_SETTINGS,
    poseConvention: 'ftcSdk',
  };
  await render(initial);
  await press('Raw optical');
  await press('Cancel debug settings');
  expect(onCancel).toHaveBeenCalledTimes(1);
  expect(onSave).not.toHaveBeenCalled();
  await act(async () => tree.update(modal(initial, false)));
  await act(async () => tree.update(modal(initial)));
  expect(byLabel('FTC SDK').props.accessibilityState.checked).toBe(true);
  expect(byLabel('Raw optical').props.accessibilityState.checked).toBe(false);
});

test('reset restores the default pose convention and Auto sizing only when applied', async () => {
  await render({
    ...DEFAULT_DEBUG_SETTINGS,
    poseConvention: 'rawOptical',
    tagSizeMode: 'custom',
    tagSizeMeters: 0.1723456789,
  });
  await press('Reset debug settings to automatic defaults');
  expect(onSave).not.toHaveBeenCalled();
  expect(byLabel('FRC / PhotonVision').props.accessibilityState.checked).toBe(
    true,
  );
  expect(byLabel('Auto (LiDAR)').props.accessibilityState.checked).toBe(true);
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith(DEFAULT_DEBUG_SETTINGS);
});

test('viewing incidence retains its native wire key and the saved pose convention', async () => {
  await render({ ...DEFAULT_DEBUG_SETTINGS, poseConvention: 'rawOptical' });
  await act(async () => {
    byLabel('Maximum viewing incidence (°)').props.onChangeText('55');
  });
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Maximum plane angle (°)' }),
  ).toHaveLength(0);
  await press('Apply debug settings');
  expect(onSave).toHaveBeenCalledWith({
    ...DEFAULT_DEBUG_SETTINGS,
    poseConvention: 'rawOptical',
    maxPlaneAngleDegrees: 55,
  });
});
