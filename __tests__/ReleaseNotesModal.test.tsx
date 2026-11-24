import React from 'react';
import { Modal, ScrollView, StyleSheet, Text } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import { ReleaseNotesModal, type AppInfo } from '../ReleaseNotesModal';
import releaseNotesDocument from '../release-notes.json';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);

const info: AppInfo = {
  bundleId: 'org.aprilfoolsar.test',
  version: '0.1.1',
  build: '6',
  buildCommit: '0123456789abcdef0123456789abcdef01234567',
  buildDateUTC: '2026-11-21T23:45:12.345Z',
  workingTreeDirty: true,
  releaseNotes: releaseNotesDocument.releases,
};
let tree: Renderer.ReactTestRenderer | undefined;
const byLabel = (accessibilityLabel: string) =>
  tree!.root.findByProps({ accessibilityLabel });
async function selectTab(label: 'Version' | 'Release notes') {
  await act(async () => byLabel(label).props.onPress());
}
afterEach(async () => {
  if (tree) {
    await act(async () => tree?.unmount());
    tree = undefined;
  }
});

test('identifies the installed version and build rather than treating the first release as current', async () => {
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal
        visible
        info={{ ...info, version: '0.1.0', build: '4' }}
        onClose={jest.fn()}
      />,
    );
  });
  await selectTab('Release notes');
  const current = tree!.root.findByProps({ testID: 'current-release' });
  const currentText = current
    .findAllByType(Text)
    .flatMap(node =>
      React.Children.toArray(node.props.children).filter(
        child => typeof child === 'string' || typeof child === 'number',
      ),
    )
    .join(' ');
  expect(currentText).toContain('Tag pose and LiDAR diagnostics');
  expect(currentText).not.toContain('Compact overlay and optional pose axes');
  expect(tree!.root.findByProps({ testID: 'release-0.1.0-5' })).toBeTruthy();
  expect(tree!.root.findByProps({ testID: 'release-0.1.1-6' })).toBeTruthy();
  expect(tree!.root.findAllByProps({ testID: 'release-0.1.0-4' })).toHaveLength(
    0,
  );
  expect(tree!.root.findByType(ScrollView)).toBeTruthy();
});

test('opens full screen with scrollable content and fixed bottom tabs and Done', async () => {
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal visible info={info} onClose={jest.fn()} />,
    );
  });
  const modal = tree!.root.findByType(Modal);
  expect(modal.props.transparent).toBe(false);
  expect(modal.props.presentationStyle).toBe('overFullScreen');
  const screen = tree!.root.findByProps({ testID: 'release.notes.screen' });
  expect(StyleSheet.flatten(screen.props.style).flex).toBe(1);
  expect(StyleSheet.flatten(screen.props.style).maxHeight).toBeUndefined();
  const navigation = tree!.root.findByProps({
    testID: 'release.notes.navigation',
  });
  const content = tree!.root.findByProps({ testID: 'release.notes.content' });
  for (const label of ['Version', 'Release notes', 'Close release notes']) {
    expect(navigation.findByProps({ accessibilityLabel: label })).toBeTruthy();
    expect(content.findAllByProps({ accessibilityLabel: label })).toHaveLength(
      0,
    );
    expect(
      StyleSheet.flatten(byLabel(label).props.style).minHeight,
    ).toBeGreaterThanOrEqual(44);
  }
  expect(byLabel('Version').props.accessibilityRole).toBe('tab');
  expect(byLabel('Release notes').props.accessibilityRole).toBe('tab');
  expect(byLabel('Version').props.accessibilityState.selected).toBe(true);
  expect(byLabel('Release notes').props.accessibilityState.selected).toBe(
    false,
  );
  expect(
    tree!.root.findByProps({ testID: 'installed-build-details' }),
  ).toBeTruthy();
  expect(tree!.root.findAllByProps({ testID: 'current-release' })).toHaveLength(
    0,
  );
});

test('bottom tabs switch between source details and release notes and reopening starts with Version', async () => {
  const onClose = jest.fn();
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal visible info={info} onClose={onClose} />,
    );
  });
  await selectTab('Release notes');
  expect(byLabel('Release notes').props.accessibilityState.selected).toBe(true);
  expect(tree!.root.findByProps({ testID: 'current-release' })).toBeTruthy();
  expect(
    tree!.root.findAllByProps({ testID: 'installed-build-details' }),
  ).toHaveLength(0);
  await selectTab('Version');
  expect(byLabel('Version').props.accessibilityState.selected).toBe(true);
  expect(
    tree!.root.findByProps({ testID: 'installed-build-details' }),
  ).toBeTruthy();
  await selectTab('Release notes');
  await act(async () => {
    tree!.update(
      <ReleaseNotesModal visible={false} info={info} onClose={onClose} />,
    );
  });
  await act(async () => {
    tree!.update(<ReleaseNotesModal visible info={info} onClose={onClose} />);
  });
  expect(byLabel('Version').props.accessibilityState.selected).toBe(true);
  expect(
    tree!.root.findByProps({ testID: 'installed-build-details' }),
  ).toBeTruthy();
  expect(onClose).not.toHaveBeenCalled();
});

test('shows the full source and exact UTC stamp and closes through button or native dismissal', async () => {
  const onClose = jest.fn();
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal visible info={info} onClose={onClose} />,
    );
  });
  const contents = JSON.stringify(tree!.toJSON());
  expect(contents).toContain(info.buildCommit);
  expect(contents).toContain(info.buildDateUTC);
  expect(contents).toContain('2026-11-21 23:45:12.345 UTC');
  expect(contents).toContain('UNCOMMITTED SOURCE CHANGES');
  await act(async () =>
    tree!.root
      .findByProps({ accessibilityLabel: 'Close release notes' })
      .props.onPress(),
  );
  expect(onClose).toHaveBeenCalledTimes(1);
  await act(async () => tree!.root.findByType(Modal).props.onRequestClose());
  await act(async () => tree!.root.findByType(Modal).props.onDismiss());
  expect(onClose).toHaveBeenCalledTimes(3);
});

test('a supplied dismissal callback runs separately after native dismissal', async () => {
  const onClose = jest.fn();
  const onDismiss = jest.fn();
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal
        visible
        info={info}
        onClose={onClose}
        onDismiss={onDismiss}
      />,
    );
  });
  await act(async () => tree!.root.findByType(Modal).props.onRequestClose());
  expect(onClose).toHaveBeenCalledTimes(1);
  expect(onDismiss).not.toHaveBeenCalled();
  await act(async () => tree!.root.findByType(Modal).props.onDismiss());
  expect(onDismiss).toHaveBeenCalledTimes(1);
  expect(onClose).toHaveBeenCalledTimes(1);
});

test('keeps the native Modal mounted while hiding so queued navigation can await dismissal', async () => {
  const onClose = jest.fn();
  const onDismiss = jest.fn();
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal
        visible
        info={info}
        onClose={onClose}
        onDismiss={onDismiss}
      />,
    );
  });
  await act(async () => {
    tree!.update(
      <ReleaseNotesModal
        visible={false}
        info={info}
        onClose={onClose}
        onDismiss={onDismiss}
      />,
    );
  });
  const modal = tree!.root.findByType(Modal);
  expect(modal.props.visible).toBe(false);
  expect(onDismiss).not.toHaveBeenCalled();
  await act(async () => modal.props.onDismiss());
  expect(onDismiss).toHaveBeenCalledTimes(1);
  expect(onClose).not.toHaveBeenCalled();
});

test('does not fabricate build details or mark a different release current when information is missing', async () => {
  await act(async () => {
    tree = Renderer.create(
      <ReleaseNotesModal visible info={null} onClose={jest.fn()} />,
    );
  });
  expect(JSON.stringify(tree!.toJSON())).toContain(
    'Build information unavailable',
  );
  expect(
    tree!.root.findAllByProps({ testID: 'installed-build-details' }),
  ).toHaveLength(0);
  await act(async () => {
    tree!.update(
      <ReleaseNotesModal
        visible
        info={{ ...info, build: '999', workingTreeDirty: false }}
        onClose={jest.fn()}
      />,
    );
  });
  expect(JSON.stringify(tree!.toJSON())).toContain('Clean source tree');
  expect(JSON.stringify(tree!.toJSON())).not.toContain(
    'UNCOMMITTED SOURCE CHANGES',
  );
  await selectTab('Release notes');
  expect(JSON.stringify(tree!.toJSON())).toContain(
    'No release notes are bundled',
  );
  expect(tree!.root.findAllByProps({ testID: 'current-release' })).toHaveLength(
    0,
  );
  await act(async () => {
    tree!.update(
      <ReleaseNotesModal visible={false} info={info} onClose={jest.fn()} />,
    );
  });
  expect(tree!.toJSON()).toBeNull();
});
