import React from 'react';
import { Alert, Linking, Modal, Text } from 'react-native';
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

test('Done and native dismissal close the modal, and reopening returns to privacy', async () => {
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
  expect(tree!.root.findByProps({ testID: 'privacy-policy' })).toBeTruthy();
  expect(tree!.root.findAllByProps({ testID: 'app-license' })).toHaveLength(0);
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
