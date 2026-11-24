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
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { AppVersionBadge } from './AppVersionBadge';
import legal from './legal-documents.json';

export type AboutPage = 'about' | 'privacy' | 'licenses' | 'sponsors';
type ContentPage = Exclude<AboutPage, 'sponsors'>;

const pageTitles: Record<ContentPage, string> = {
  about: 'About',
  privacy: 'Privacy',
  licenses: 'Licenses & notices',
};
const contentPage = (page: AboutPage): ContentPage =>
  page === 'sponsors' ? 'about' : page;

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
  initialPage = 'about',
  appVersion,
  onOpenVersion,
  onDismiss,
}: {
  visible: boolean;
  onClose: () => void;
  initialPage?: AboutPage;
  appVersion?: { version: string; build: string } | null;
  onOpenVersion?: () => void;
  onDismiss?: () => void;
}) {
  const inset = useSafeAreaInsets();
  const [page, setPage] = useState<ContentPage>(() => contentPage(initialPage));
  useEffect(() => {
    if (visible) {
      setPage(contentPage(initialPage));
    }
  }, [visible, initialPage]);
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
      visible={visible}
      transparent={false}
      presentationStyle="overFullScreen"
      animationType="slide"
      supportedOrientations={[
        'portrait',
        'landscape-left',
        'landscape-right',
        'portrait-upside-down',
      ]}
      onRequestClose={onClose}
      onDismiss={onDismiss}
    >
      <View
        style={[
          s.screen,
          {
            paddingTop: inset.top,
            paddingBottom: inset.bottom,
            paddingLeft: inset.left,
            paddingRight: inset.right,
          },
        ]}
        accessibilityViewIsModal
        testID="about.screen"
      >
        <View style={s.header}>
          <Text style={s.title} accessibilityRole="header">
            {page === 'about' ? 'About and sponsors' : pageTitles[page]}
          </Text>
        </View>
        <ScrollView
          key={page}
          style={s.scroll}
          contentContainerStyle={s.content}
          testID="about.content"
        >
          {page === 'about' ? (
            <View style={s.aboutContent} testID="about-and-sponsors">
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
              <View style={s.sponsors}>
                <Text style={s.sectionTitle} accessibilityRole="header">
                  Sponsors
                </Text>
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
            </View>
          ) : page === 'privacy' ? (
            <Text selectable style={s.text} testID="privacy-policy">
              {legal.privacy}
            </Text>
          ) : (
            <>
              <Text selectable style={s.text} testID="app-license">
                {legal.license}
              </Text>
              <Text selectable style={s.text} testID="third-party-notices">
                {legal.thirdPartyNotices}
              </Text>
            </>
          )}
        </ScrollView>
        <View style={s.navigation} testID="about.bottomNav">
          {(['about', 'privacy', 'licenses'] as const).map(item => (
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
          <Pressable
            accessibilityRole="button"
            accessibilityLabel="Close about and privacy"
            onPress={onClose}
            style={s.close}
          >
            <Text style={s.link}>Done</Text>
          </Pressable>
        </View>
      </View>
      <AppVersionBadge info={appVersion} onPress={onOpenVersion} />
    </Modal>
  );
}

const s = StyleSheet.create({
  screen: { flex: 1, minHeight: 0, backgroundColor: '#071426' },
  header: {
    minHeight: 52,
    paddingLeft: 20,
    paddingRight: 132,
    paddingVertical: 12,
  },
  title: { color: '#F3F8FD', fontSize: 22, fontWeight: '700' },
  navigation: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderTopWidth: 1,
    borderTopColor: '#24415A',
    backgroundColor: '#102239',
  },
  close: {
    minHeight: 44,
    minWidth: 60,
    flexGrow: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 8,
  },
  tab: {
    minHeight: 44,
    flexGrow: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingHorizontal: 8,
    borderBottomWidth: 2,
    borderBottomColor: 'transparent',
  },
  selected: { borderBottomColor: '#A1D18B' },
  scroll: { flex: 1, minHeight: 0 },
  content: {
    padding: 20,
    paddingBottom: 36,
    gap: 16,
    width: '100%',
    maxWidth: 900,
    alignSelf: 'center',
  },
  aboutContent: { gap: 16 },
  logoCard: {
    backgroundColor: '#FFFFFF',
    borderRadius: 12,
    padding: 16,
    alignItems: 'center',
  },
  logo: { width: '100%', maxWidth: 292, height: 76 },
  appName: { color: '#F3F8FD', fontSize: 20, fontWeight: '700' },
  sectionTitle: { color: '#F3F8FD', fontSize: 20, fontWeight: '700' },
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
