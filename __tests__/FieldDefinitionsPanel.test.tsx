import React from 'react';
import { Keyboard, ScrollView, Share, Text, TextInput } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import {
  FieldDefinitionsPanel,
  type FieldEngine,
  type FieldStatus,
} from '../FieldDefinitionsPanel';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);

const initial: FieldStatus = {
  packageId: 'frc-2026-welded',
  label: 'FRC 2026 REBUILT · Welded',
  packageHash: 'abc123',
  coordinateFrame: 'wpilib-blue-z-up',
  candidateId: 1,
  alignment: 'unaligned',
  seenCount: 1,
  expectedCount: 32,
  seenTags: [
    {
      id: 1,
      count: 3,
      nominalPosition: [0, 2, 1.5],
      observedPosition: null,
      frameId: 'representative-frame',
      segmentId: 'source-segment',
      timestamp: 123.456,
      reason: 'Alignment unavailable',
    },
  ],
  yaml: 'schemaVersion: 1\nseenTags:\n  - id: 1\n',
};
const packages = [
  {
    id: 'frc-2026-welded',
    label: initial.label!,
    program: 'FRC',
    season: '2026',
    variant: 'Welded',
    tagCount: 32,
  },
  {
    id: 'frc-2026-andymark',
    label: 'FRC 2026 REBUILT · AndyMark',
    program: 'FRC',
    season: '2026',
    variant: 'AndyMark',
    tagCount: 32,
  },
];
let engine: jest.Mocked<FieldEngine>;
let tree: Renderer.ReactTestRenderer;
const onClose = jest.fn();
const onChange = jest.fn();
const button = (label: string) =>
  tree.root.findByProps({ accessibilityLabel: label });
const text = () =>
  tree.root
    .findAllByType(Text)
    .map(node => node.props.children)
    .flat(Infinity)
    .join(' ')
    .replace(/\s+/g, ' ');
const render = async (
  props: Partial<React.ComponentProps<typeof FieldDefinitionsPanel>> = {},
) => {
  await act(async () => {
    tree = Renderer.create(
      <FieldDefinitionsPanel
        visible
        engine={engine}
        field={initial}
        onClose={onClose}
        onChange={onChange}
        {...props}
      />,
    );
  });
};
beforeEach(() => {
  jest.clearAllMocks();
  engine = {
    getFieldCatalog: jest.fn().mockResolvedValue({ packages }),
    getFieldDefinition: jest.fn().mockResolvedValue({
      id: initial.packageId,
      yaml: 'schemaVersion: 1\nprogram: FRC\n',
    }),
    selectField: jest.fn().mockResolvedValue({
      ...initial,
      packageId: packages[1].id,
      label: packages[1].label,
    }),
    importFieldDefinition: jest
      .fn()
      .mockResolvedValue({ ...initial, packageId: 'custom-field' }),
    getFieldWalk: jest.fn().mockResolvedValue(initial),
    getSavedFieldWalk: jest
      .fn()
      .mockResolvedValue({ yaml: initial.yaml, field: initial }),
    clearFieldAlignment: jest
      .fn()
      .mockResolvedValue({ ...initial, alignment: 'unaligned' }),
    recheckFieldAlignment: jest
      .fn()
      .mockResolvedValue({ ...initial, alignment: 'waiting' }),
    alignFieldUnverified: jest
      .fn()
      .mockResolvedValue({ ...initial, alignment: 'provisional' }),
  };
});
afterEach(async () => {
  if (tree) {
    await act(async () => tree.unmount());
  }
});

test('field selection is a draft until applied; cancel preserves the package', async () => {
  await render();
  await act(async () => button('Choose field').props.onPress());
  await act(async () => button(`Select ${packages[1].label}`).props.onPress());
  expect(engine.selectField).not.toHaveBeenCalled();
  await act(async () => button('Cancel field selection').props.onPress());
  expect(onClose).toHaveBeenCalledTimes(1);
  expect(engine.selectField).not.toHaveBeenCalled();
});

test('applying the explicit variant sends its package id and updates status', async () => {
  await render();
  await act(async () => button('Choose field').props.onPress());
  await act(async () => button(`Select ${packages[1].label}`).props.onPress());
  await act(async () => button('Use selected field').props.onPress());
  expect(engine.selectField).toHaveBeenCalledWith('frc-2026-andymark');
  expect(onChange).toHaveBeenCalledWith(
    expect.objectContaining({ packageId: 'frc-2026-andymark' }),
  );
  expect(text()).toContain('Tags seen:');
});

test('recording pins the field and blocks even a stale apply handler', async () => {
  await render({ recording: true });
  await act(async () => button('Choose field').props.onPress());
  expect(button(`Select ${packages[1].label}`).props.disabled).toBe(true);
  expect(button('Use selected field').props.disabled).toBe(true);
  expect(button('Import YAML or JSON').props.disabled).toBe(true);
  await act(async () => button('Use selected field').props.onPress());
  expect(engine.selectField).not.toHaveBeenCalled();
  expect(text()).toContain('Stop and save the walk before changing its field.');
});

test('zero height and tilt are displayed as values, with expected/observed differences', async () => {
  const field: FieldStatus = {
    ...initial,
    checks: {
      height: { expected: 0, observed: 0, tolerance: 0.05, status: 'passed' },
      tilt: { expected: 0, observed: 2, tolerance: 3, status: 'passed' },
    },
  };
  engine.getFieldWalk.mockResolvedValue(field);
  await render({ field });
  expect(text()).toContain('expected 0.0');
  expect(text()).toContain('observed 0.0');
  expect(text()).toContain('allowed ±5.0');
  expect(text()).toContain('Published XYZ:');
  expect(text()).toContain('XYZ field frame: wpilib-blue-z-up');
  expect(text()).toContain('0.000, 2.000, 1.500 m');
  expect(text()).toContain('Observed XYZ:');
  expect(text()).toContain('unavailable');
  expect(text()).toContain('Source frame: representative-frame');
  expect(text()).toContain('segment source-segment');
  expect(text()).toContain('source time 123.456 s');
});

test('failed checks retain the warning and do not offer manual bypass', async () => {
  const field: FieldStatus = {
    ...initial,
    checks: {
      height: {
        expected: 1.5,
        observed: 1.7,
        tolerance: 0.05,
        status: 'failed',
      },
      tilt: { expected: 0, observed: 0, tolerance: 3, status: 'passed' },
    },
    warnings: [
      'Tag 1: expected height 150 cm, observed 170 cm. Field not aligned.',
    ],
  };
  engine.getFieldWalk.mockResolvedValue(field);
  await render({ field });
  expect(text()).toContain('Field not aligned.');
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Align without height check',
    }),
  ).toHaveLength(0);
  await act(async () => button('Recheck field alignment').props.onPress());
  expect(engine.recheckFieldAlignment).toHaveBeenCalledTimes(1);
});

test('missing floor height remains unverified and exposes an explicit fallback', async () => {
  const field: FieldStatus = {
    ...initial,
    checks: {
      height: {
        expected: 1.5,
        observed: null,
        status: 'unavailable',
        reason: 'Select the field floor to check height.',
      },
      tilt: { expected: 0, observed: 0, status: 'passed' },
      gravity: { expected: 0, observed: 0, status: 'passed' },
    },
  };
  engine.getFieldWalk.mockResolvedValue(field);
  await render({ field });
  expect(text()).toContain('observed unavailable');
  expect(text()).toContain('Select the field floor to check height.');
  await act(async () => button('Align without height check').props.onPress());
  expect(engine.alignFieldUnverified).toHaveBeenCalledTimes(1);
});

test('definition viewer displays canonical YAML rather than serializing UI state', async () => {
  await render();
  await act(async () => button('View YAML').props.onPress());
  expect(engine.getFieldDefinition).toHaveBeenCalledWith('frc-2026-welded');
  expect(button('Field YAML document').props.children).toBe(
    'schemaVersion: 1\nprogram: FRC\n',
  );
  expect(button('Field YAML document').props.accessibilityValue).toEqual({
    text: 'schemaVersion: 1\nprogram: FRC\n',
  });
});

test('JSON import goes through native validation and uses the imported field', async () => {
  await render();
  await act(async () => button('Import YAML or JSON').props.onPress());
  const input = tree.root.findByType(TextInput);
  const source = '{"schemaVersion":1,"program":"FRC"}';
  await act(async () => input.props.onChangeText(source));
  await act(async () =>
    button('Validate and use imported field').props.onPress(),
  );
  expect(engine.importFieldDefinition).toHaveBeenCalledWith(source);
  expect(onChange).toHaveBeenCalledWith(
    expect.objectContaining({ packageId: 'custom-field' }),
  );
});

test('import provides an accessible keyboard dismissal without clearing the draft', async () => {
  const dismiss = jest.spyOn(Keyboard, 'dismiss').mockImplementation(() => {});
  await render();
  await act(async () => button('Import YAML or JSON').props.onPress());
  await act(async () =>
    tree.root.findByType(TextInput).props.onChangeText('schemaVersion: 1'),
  );
  const scroll = tree.root.findByType(ScrollView);
  expect(scroll.props.automaticallyAdjustKeyboardInsets).toBe(true);
  expect(scroll.props.keyboardDismissMode).toBe('on-drag');
  expect(scroll.props.keyboardShouldPersistTaps).toBe('handled');
  await act(async () => button('Hide keyboard').props.onPress());
  expect(dismiss).toHaveBeenCalledTimes(1);
  expect(tree.root.findByType(TextInput).props.value).toBe('schemaVersion: 1');
  dismiss.mockRestore();
});

test('invalid import reports a useful error and preserves the existing walk', async () => {
  engine.importFieldDefinition.mockRejectedValue(
    new Error('tags[0].id: duplicate id'),
  );
  await render();
  await act(async () => button('Import YAML or JSON').props.onPress());
  await act(async () =>
    tree.root.findByType(TextInput).props.onChangeText('bad: input'),
  );
  await act(async () =>
    button('Validate and use imported field').props.onPress(),
  );
  expect(text()).toContain('tags[0].id: duplicate id');
  expect(onChange).not.toHaveBeenCalled();
});

test('YAML is the default walk share format and JSON/CSV remain available', async () => {
  const sharing = jest
    .spyOn(Share, 'share')
    .mockResolvedValue({ action: Share.sharedAction, activityType: undefined });
  await render();
  await act(async () => button('Share walk YAML').props.onPress());
  expect(sharing).toHaveBeenLastCalledWith(
    expect.objectContaining({ message: initial.yaml }),
  );
  await act(async () => button('Share walk JSON').props.onPress());
  expect(JSON.parse(sharing.mock.calls.at(-1)![0].message!)).toEqual(initial);
  await act(async () => button('Share walk CSV').props.onPress());
  expect(sharing.mock.calls.at(-1)![0].message).toContain(
    '1,tag36h11,3,0,2,1.5',
  );
  sharing.mockRestore();
});

test('saved observations link to recorded time and keep their original source identity', async () => {
  const onOpenEvidence = jest.fn();
  const tag = { ...initial.seenTags![0], videoTimeSeconds: 0.25 };
  engine.getSavedFieldWalk.mockResolvedValue({
    yaml: initial.yaml!,
    field: { ...initial, seenTags: [tag] },
  });
  await render({
    savedSession: { id: 'saved-id', name: 'Blue field' },
    onOpenEvidence,
  });
  expect(text()).toContain('Source frame: representative-frame');
  expect(text()).toContain('source time 123.456 s');
  expect(text()).toContain('the source frame may be metadata only');
  await act(async () => button('Open observation for tag 1').props.onPress());
  expect(onOpenEvidence).toHaveBeenCalledWith(tag);
});

test('missing recorded time shows unavailable instead of offering a zero-time observation link', async () => {
  await render({
    savedSession: { id: 'saved-id', name: 'Blue field' },
    onOpenEvidence: jest.fn(),
  });
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Open observation for tag 1',
    }),
  ).toHaveLength(0);
  expect(text()).toContain('Recorded-time video link unavailable');
});

test('saved walks are read-only, show their saved YAML and share the original summary', async () => {
  const sharing = jest
    .spyOn(Share, 'share')
    .mockResolvedValue({ action: Share.sharedAction, activityType: undefined });
  await render({ savedSession: { id: 'saved-id', name: 'Blue field' } });
  expect(engine.getSavedFieldWalk).toHaveBeenCalledWith('saved-id');
  expect(engine.getFieldCatalog).not.toHaveBeenCalled();
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Choose field' }),
  ).toHaveLength(0);
  expect(
    tree.root.findAllByProps({ accessibilityLabel: 'Clear field alignment' }),
  ).toHaveLength(0);
  await act(async () => button('View YAML').props.onPress());
  expect(button('Field YAML document').props.children).toBe(initial.yaml);
  await act(async () => button('Tags seen').props.onPress());
  await act(async () => button('Share walk YAML').props.onPress());
  expect(sharing).toHaveBeenLastCalledWith(
    expect.objectContaining({ message: initial.yaml }),
  );
  sharing.mockRestore();
});

test('missing tilt never offers a height-only manual bypass', async () => {
  const field: FieldStatus = {
    ...initial,
    checks: {
      height: { expected: 1.5, observed: null, status: 'unavailable' },
      tilt: { expected: 0, observed: null, status: 'unavailable' },
      gravity: { expected: 0, observed: 0, status: 'passed' },
    },
  };
  engine.getFieldWalk.mockResolvedValue(field);
  await render({ field });
  expect(
    tree.root.findAllByProps({
      accessibilityLabel: 'Align without height check',
    }),
  ).toHaveLength(0);
});

test('native package hash and gravity-only angular difference remain visible', async () => {
  const field: FieldStatus = {
    ...initial,
    packageHash: undefined,
    packageSha256: 'native-sha',
    checks: {
      gravity: { difference: 2.5, tolerance: 7, status: 'pass' },
    },
  };
  engine.getFieldWalk.mockResolvedValue(field);
  await render({ field });
  expect(text()).toContain('native-sha');
  expect(text()).toContain('difference 2.5 °');
});

test('catalog loading failures explain the native validation problem', async () => {
  engine.getFieldCatalog.mockResolvedValue({
    packages: [],
    error: 'Bundled catalog hash mismatch',
  });
  await render();
  expect(text()).toContain('Bundled catalog hash mismatch');
});
