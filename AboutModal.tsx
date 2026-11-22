import React, { useEffect, useState } from 'react';
import {
  Alert,
  Image,
  Linking,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import legal from './legal-documents.json';

export type AboutPage = 'privacy' | 'licenses' | 'sponsors';

const pageTitles: Record<AboutPage, string> = {
  privacy: 'Privacy',
  licenses: 'Licenses & notices',
  sponsors: 'Sponsors',
};

const sponsors = [
  {
    name: 'Don Wood Foundation',
    url: 'https://www.donwoodfoundation.org/',
    domain: 'donwoodfoundation.org',
  },
  {
    name: 'Medical Informatics Engineering',
    url: 'https://mieweb.org/',
    domain: 'mieweb.org',
  },
];

export function AboutModal({
  visible,
  onClose,
  initialPage = 'privacy',
}: {
  visible: boolean;
  onClose: () => void;
  initialPage?: AboutPage;
}) {
  const [page, setPage] = useState<AboutPage>(initialPage);
  useEffect(() => {
    if (visible) {
      setPage(initialPage);
    }
  }, [visible, initialPage]);
  if (!visible) {
    return null;
  }
  const visit = async (
    url = 'https://refineryrobotics.org',
    name = 'The REFINERY',
    fallback = 'Visit refineryrobotics.org for support.',
  ) => {
    try {
      await Linking.openURL(url);
    } catch {
      Alert.alert(name, fallback);
    }
  };
  return (
    <Modal
      visible
      transparent
      animationType="slide"
      supportedOrientations={[
        'portrait',
        'landscape-left',
        'landscape-right',
        'portrait-upside-down',
      ]}
      onRequestClose={onClose}
    >
      <SafeAreaView style={s.backdrop} accessibilityViewIsModal>
        <View style={s.sheet}>
          <View style={s.header}>
            <Text style={s.title} accessibilityRole="header">
              {page === 'sponsors' ? 'Sponsors' : 'About & privacy'}
            </Text>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Close about and privacy"
              onPress={onClose}
              style={s.close}
            >
              <Text style={s.link}>Done</Text>
            </Pressable>
          </View>
          <View style={s.tabs}>
            {(['privacy', 'licenses', 'sponsors'] as const).map(item => (
              <Pressable
                key={item}
                accessibilityRole="tab"
                accessibilityState={{ selected: page === item }}
                onPress={() => setPage(item)}
                style={[s.tab, page === item && s.selected]}
              >
                <Text style={s.link}>{pageTitles[item]}</Text>
              </Pressable>
            ))}
          </View>
          <ScrollView
            key={page}
            style={s.scroll}
            contentContainerStyle={s.content}
          >
            <View style={s.logoCard}>
              <Image
                source={require('./assets/brand/refinery-logo.png')}
                style={s.logo}
                resizeMode="contain"
                accessibilityLabel="The REFINERY"
              />
            </View>
            <Text style={s.appName}>April Fools AR by The REFINERY</Text>
            <Text style={s.text}>
              A BioNanomics project · © 2026 BioNanomics
            </Text>
            <Pressable
              accessibilityRole="link"
              accessibilityLabel="The REFINERY website and support"
              onPress={() => visit()}
              style={s.website}
            >
              <Text style={s.link}>
                refineryrobotics.org · Website & support ↗
              </Text>
            </Pressable>
            {page === 'privacy' ? (
              <Text selectable style={s.text} testID="privacy-policy">
                {legal.privacy}
              </Text>
            ) : page === 'licenses' ? (
              <>
                <Text selectable style={s.text} testID="app-license">
                  {legal.license}
                </Text>
                <Text selectable style={s.text} testID="third-party-notices">
                  {legal.thirdPartyNotices}
                </Text>
              </>
            ) : (
              <View style={s.sponsors}>
                <Text style={s.text}>
                  Thank you to our sponsors for supporting The REFINERY.
                </Text>
                {sponsors.map(sponsor => (
                  <Pressable
                    key={sponsor.url}
                    accessibilityRole="link"
                    accessibilityLabel={`${sponsor.name} website`}
                    accessibilityHint="Opens the sponsor website in your browser"
                    onPress={() =>
                      visit(
                        sponsor.url,
                        sponsor.name,
                        `Visit ${sponsor.domain}.`,
                      )
                    }
                    style={s.sponsorCard}
                  >
                    <Text style={s.sponsorName}>{sponsor.name}</Text>
                    <Text style={s.link}>{sponsor.domain} ↗</Text>
                  </Pressable>
                ))}
              </View>
            )}
          </ScrollView>
        </View>
      </SafeAreaView>
    </Modal>
  );
}

const s = StyleSheet.create({
  backdrop: {
    flex: 1,
    padding: 12,
    backgroundColor: '#000000AA',
    justifyContent: 'center',
  },
  sheet: {
    flex: 1,
    width: '100%',
    maxWidth: 800,
    maxHeight: 900,
    alignSelf: 'center',
    borderRadius: 18,
    overflow: 'hidden',
    backgroundColor: '#071426',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 20,
    paddingVertical: 8,
    gap: 12,
  },
  title: { flex: 1, color: '#F3F8FD', fontSize: 22, fontWeight: '700' },
  close: { minHeight: 44, minWidth: 60, justifyContent: 'center' },
  tabs: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    paddingHorizontal: 20,
    columnGap: 16,
  },
  tab: {
    minHeight: 44,
    justifyContent: 'center',
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  selected: { borderBottomColor: '#A1D18B' },
  scroll: { flex: 1, minHeight: 0 },
  content: { padding: 20, paddingBottom: 36, gap: 16 },
  logoCard: {
    backgroundColor: '#FFFFFF',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  logo: { width: '100%', maxWidth: 292, height: 76 },
  appName: { color: '#F3F8FD', fontSize: 20, fontWeight: '700' },
  text: { color: '#D6E2EC', fontSize: 15, lineHeight: 23 },
  link: { color: '#A1D18B', fontSize: 14, fontWeight: '600' },
  website: { minHeight: 44, justifyContent: 'center' },
  sponsors: { gap: 16 },
  sponsorCard: {
    minHeight: 80,
    padding: 18,
    gap: 8,
    backgroundColor: '#102239',
    borderWidth: 1,
    borderColor: '#24415A',
    borderRadius: 12,
  },
  sponsorName: { color: '#F3F8FD', fontSize: 18, fontWeight: '600' },
});
