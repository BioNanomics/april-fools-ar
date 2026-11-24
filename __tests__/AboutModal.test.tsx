import React from 'react';
import { Alert, Linking, Modal, StyleSheet, Text } from 'react-native';
import Renderer, { act } from 'react-test-renderer';
import { AboutModal } from '../AboutModal';
import legal from '../legal-documents.json';

jest.mock(
  'react-native-safe-area-context',
  () => require('react-native-safe-area-context/jest/mock').default,
);

let tree: Renderer.ReactTestRenderer | undefined;
afterEach(async () => {
  if (tree) {
    await act(async () => tree?.unmount());
    tree = undefined;
  }
  jest.restoreAllMocks();
});

const pressTab = async (title: string) => {
  const tab = tree!.root
    .findAllByProps({ accessibilityRole: 'tab' })
    .find(item =>
      item.findAllByType(Text).some(label => label.props.children === title),
    );
  expect(tab).toBeDefined();
  await act(async () => tab!.props.onPress());
};

test('privacy and complete app and third-party licenses are available without opening a website', async () => {
  const openURL = jest.spyOn(Linking, 'openURL').mockResolvedValue(undefined);
  await act(async () => {
    tree = Renderer.create(<AboutModal visible onClose={jest.fn()} />);
  });
  await pressTab('Privacy');
  expect(
    tree!.root.findByProps({ testID: 'privacy-policy' }).props.children,
  ).toBe(legal.privacy);
  await pressTab('Licenses & notices');
  expect(tree!.root.findByProps({ testID: 'app-license' }).props.children).toBe(
    legal.license,
  );
  expect(
    tree!.root.findByProps({ testID: 'third-party-notices' }).props.children,
  ).toBe(legal.thirdPartyNotices);
  expect(legal.license).toContain('Copyright (c) 2026 BioNanomics');
  expect(legal.thirdPartyNotices).toContain(
    'The Regents of The University of Michigan',
  );
  expect(openURL).not.toHaveBeenCalled();
});

test('Done and native dismissal close the modal, and reopening returns to About with sponsors', async () => {
  const onClose = jest.fn();
  await act(async () => {
    tree = Renderer.create(<AboutModal visible onClose={onClose} />);
  });
  await pressTab('Licenses & notices');
  await act(async () => {
    tree!.root
      .findByProps({ accessibilityLabel: 'Close about and privacy' })
      .props.onPress();
    tree!.root.findByType(Modal).props.onRequestClose();
  });
  expect(onClose).toHaveBeenCalledTimes(2);
  await act(async () => {
    tree!.update(<AboutModal visible={false} onClose={onClose} />);
  });
  expect(tree!.toJSON()).toBeNull();
  await act(async () => {
    tree!.update(<AboutModal visible onClose={onClose} />);
  });
  expect(tree!.root.findByProps({ testID: 'about-and-sponsors' })).toBeTruthy();
  expect(tree!.root.findAllByProps({ testID: 'privacy-policy' })).toHaveLength(
    0,
  );
  expect(tree!.root.findAllByProps({ testID: 'app-license' })).toHaveLength(0);
});

test('About combines app details and both sponsors in a full-screen page with bottom navigation', async () => {
  const openURL = jest.spyOn(Linking, 'openURL').mockResolvedValue(undefined);
  const onOpenVersion = jest.fn();
  const onDismiss = jest.fn();
  await act(async () => {
    tree = Renderer.create(
      <AboutModal
        visible
        onClose={jest.fn()}
        appVersion={{ version: '0.8.0', build: '28' }}
        onOpenVersion={onOpenVersion}
        onDismiss={onDismiss}
      />,
    );
  });
  const modal = tree!.root.findByType(Modal);
  expect(modal.props.presentationStyle).toBe('overFullScreen');
  expect(modal.props.transparent).toBe(false);
  const contents = JSON.stringify(tree!.toJSON());
  expect(contents).toContain('April Fools AR by The REFINERY');
  expect(contents).toContain('A BioNanomics project');
  expect(contents).toContain('Don Wood Foundation');
  expect(contents).toContain('Medical Informatics Engineering');
  const nav = tree!.root.findByProps({ testID: 'about.bottomNav' });
  expect(nav.findAllByProps({ accessibilityRole: 'tab' })).not.toHaveLength(0);
  const hostTabs = nav.findAll(
    node =>
      typeof node.type === 'string' && node.props.accessibilityRole === 'tab',
  );
  expect(hostTabs).toHaveLength(3);
  expect(hostTabs.map(tab => tab.findByType(Text).props.children)).toEqual([
    'About',
    'Privacy',
    'Licenses & notices',
  ]);
  for (const tab of hostTabs) {
    expect(
      StyleSheet.flatten(tab.props.style).minHeight,
    ).toBeGreaterThanOrEqual(44);
  }
  const close = nav.findByProps({
    accessibilityLabel: 'Close about and privacy',
  });
  expect(
    StyleSheet.flatten(close.props.style).minHeight,
  ).toBeGreaterThanOrEqual(44);
  await act(async () =>
    tree!.root.findByProps({ testID: 'app.versionBadge' }).props.onPress(),
  );
  expect(onOpenVersion).toHaveBeenCalledTimes(1);
  await act(async () => modal.props.onDismiss());
  expect(onDismiss).toHaveBeenCalledTimes(1);
  expect(openURL).not.toHaveBeenCalled();
});

test('the legacy Sponsors entry opens the combined About page and sponsor links remain explicit', async () => {
  const openURL = jest.spyOn(Linking, 'openURL').mockResolvedValue(undefined);
  await act(async () => {
    tree = Renderer.create(
      <AboutModal visible initialPage="sponsors" onClose={jest.fn()} />,
    );
  });
  expect(tree!.root.findByProps({ testID: 'about-and-sponsors' })).toBeTruthy();
  await act(async () =>
    tree!.root
      .findByProps({ accessibilityLabel: 'Don Wood Foundation website' })
      .props.onPress(),
  );
  expect(openURL).toHaveBeenCalledWith('https://www.donwoodfoundation.org/');
  await pressTab('Privacy');
  expect(
    tree!.root.findAllByProps({ testID: 'about-and-sponsors' }),
  ).toHaveLength(0);
  await pressTab('About');
  expect(tree!.root.findByProps({ testID: 'about-and-sponsors' })).toBeTruthy();
});

test('website opens only on request and supplies the support address when opening fails', async () => {
  const openURL = jest
    .spyOn(Linking, 'openURL')
    .mockRejectedValue(new Error('Browser unavailable'));
  const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
  await act(async () => {
    tree = Renderer.create(<AboutModal visible onClose={jest.fn()} />);
  });
  await act(async () =>
    tree!.root
      .findByProps({ accessibilityLabel: 'The REFINERY website and support' })
      .props.onPress(),
  );
  expect(openURL).toHaveBeenCalledWith('https://refineryrobotics.org');
  expect(alert).toHaveBeenCalledWith(
    'The REFINERY',
    'Visit refineryrobotics.org for support.',
  );
});
