import React, { useEffect, useState } from 'react';
import {
  Alert,
  KeyboardAvoidingView,
  Modal,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  TextInput,
  View,
  useWindowDimensions,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

export type DebugSettings = {
  tagSizeMeters: number;
  maxDistanceMeters: number;
  maxPlaneAngleDegrees: number;
  warningDepthDifferenceMeters: number;
  rejectDepthDifferenceMeters: number;
  distanceDeltaThresholdMeters: number;
  maxReprojectionErrorPixels: number;
  tagSizeSource?: string;
  showPoseAxes?: boolean;
  showImperialHeight?: boolean;
  levelFloorWithGravity?: boolean;
};

export const DEFAULT_DEBUG_SETTINGS: DebugSettings = {
  tagSizeMeters: 0.1651,
  maxDistanceMeters: 5,
  maxPlaneAngleDegrees: 60,
  warningDepthDifferenceMeters: 0.1,
  rejectDepthDifferenceMeters: 0.15,
  distanceDeltaThresholdMeters: 0.15,
  maxReprojectionErrorPixels: 3,
  showPoseAxes: false,
  showImperialHeight: true,
  levelFloorWithGravity: false,
};

type SettingsKey = Exclude<
  keyof DebugSettings,
  | 'tagSizeSource'
  | 'showPoseAxes'
  | 'showImperialHeight'
  | 'levelFloorWithGravity'
>;
const fields: {
  key: SettingsKey;
  label: string;
  scale: number;
  hint: string;
}[] = [
  {
    key: 'tagSizeMeters',
    label: 'Tag width (mm)',
    scale: 1000,
    hint: 'Between the detected black/white border corners, not the paper edges.',
  },
  {
    key: 'maxDistanceMeters',
    label: 'Maximum range (m)',
    scale: 1,
    hint: 'Camera-to-tag distance, including horizontal and vertical offset.',
  },
  {
    key: 'maxPlaneAngleDegrees',
    label: 'Maximum plane angle (°)',
    scale: 1,
    hint: '0° is head-on; 90° is edge-on.',
  },
  {
    key: 'distanceDeltaThresholdMeters',
    label: 'Distance delta threshold (cm)',
    scale: 100,
    hint: 'Show LiDAR Δ only when the camera-to-tag distances differ by more than this.',
  },
  {
    key: 'warningDepthDifferenceMeters',
    label: 'Depth warning (cm)',
    scale: 100,
    hint: 'Turn amber when LiDAR and pose Z differ by more than this.',
  },
  {
    key: 'rejectDepthDifferenceMeters',
    label: 'Depth rejection (cm)',
    scale: 100,
    hint: 'Turn red above this difference.',
  },
  {
    key: 'maxReprojectionErrorPixels',
    label: 'Maximum reprojection error (px)',
    scale: 1,
    hint: 'RMS error of the four projected tag corners.',
  },
];

type Draft = Record<SettingsKey, string>;
const makeDraft = (settings: DebugSettings) =>
  Object.fromEntries(
    fields.map(f => [
      f.key,
      String(
        Number(
          (
            (settings[f.key] ?? DEFAULT_DEBUG_SETTINGS[f.key]) * f.scale
          ).toFixed(4),
        ),
      ),
    ]),
  ) as Draft;

export function parseDebugSettings(draft: Draft): DebugSettings {
  const result: DebugSettings = { ...DEFAULT_DEBUG_SETTINGS };
  for (const field of fields) {
    result[field.key] =
      Number(draft[field.key].trim().replace(',', '.')) / field.scale;
  }
  if (
    result.distanceDeltaThresholdMeters < 0 ||
    result.distanceDeltaThresholdMeters > 10
  ) {
    throw new Error('Distance delta threshold must be between 0 and 1,000 cm.');
  }
  if (
    fields.some(f => !draft[f.key].trim() || !Number.isFinite(result[f.key]))
  ) {
    throw new Error('Enter a number in every field.');
  }
  if (
    result.tagSizeMeters <= 0 ||
    result.maxDistanceMeters <= 0 ||
    result.maxReprojectionErrorPixels <= 0
  ) {
    throw new Error(
      'Tag width, range, and reprojection limit must be positive.',
    );
  }
  if (result.maxPlaneAngleDegrees <= 0 || result.maxPlaneAngleDegrees > 90) {
    throw new Error(
      'Plane angle must be greater than 0° and no more than 90°.',
    );
  }
  if (
    result.warningDepthDifferenceMeters < 0 ||
    result.rejectDepthDifferenceMeters <= result.warningDepthDifferenceMeters
  ) {
    throw new Error(
      'Depth rejection must be greater than the nonnegative warning threshold.',
    );
  }
  return result;
}

export function DebugSettingsModal({
  visible,
  initialSettings,
  onCancel,
  onSave,
  onMeasure,
}: {
  visible: boolean;
  initialSettings: DebugSettings;
  onCancel: () => void;
  onSave: (settings: DebugSettings) => Promise<void>;
  onMeasure: () => void;
}) {
  const inset = useSafeAreaInsets();
  const { width, height } = useWindowDimensions();
  const horizontalPadding = 16;
  const availableWidth =
    width - inset.left - inset.right - horizontalPadding * 2;
  const columns = availableWidth >= 660;
  const compact = height < 500;
  const [draft, setDraft] = useState<Draft>(() => makeDraft(initialSettings));
  const [saving, setSaving] = useState(false);
  const [resetToDefaults, setResetToDefaults] = useState(false);
  const [showPoseAxes, setShowPoseAxes] = useState(
    initialSettings.showPoseAxes ?? false,
  );
  const [showImperialHeight, setShowImperialHeight] = useState(
    initialSettings.showImperialHeight ?? true,
  );
  const [levelFloorWithGravity, setLevelFloorWithGravity] = useState(
    initialSettings.levelFloorWithGravity ?? false,
  );
  useEffect(() => {
    if (visible) {
      setDraft(makeDraft(initialSettings));
      setResetToDefaults(false);
      setShowPoseAxes(initialSettings.showPoseAxes ?? false);
      setShowImperialHeight(initialSettings.showImperialHeight ?? true);
      setLevelFloorWithGravity(initialSettings.levelFloorWithGravity ?? false);
    }
  }, [visible, initialSettings]);
  if (!visible) {
    return null;
  }
  const save = async () => {
    try {
      const values = parseDebugSettings(draft);
      values.showPoseAxes = showPoseAxes;
      values.showImperialHeight = showImperialHeight;
      values.levelFloorWithGravity = levelFloorWithGravity;
      // Display rounding must not turn a threshold-only edit into a new tag width.
      if (
        !resetToDefaults &&
        draft.tagSizeMeters === makeDraft(initialSettings).tagSizeMeters
      ) {
        values.tagSizeMeters = initialSettings.tagSizeMeters;
      }
      setSaving(true);
      await onSave(values);
    } catch (error) {
      Alert.alert(
        'Debug settings',
        error instanceof Error ? error.message : String(error),
      );
    } finally {
      setSaving(false);
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
      onRequestClose={onCancel}
    >
      <KeyboardAvoidingView
        style={[
          s.backdrop,
          {
            paddingTop: inset.top + (compact ? 8 : 20),
            paddingBottom: inset.bottom + (compact ? 8 : 20),
            paddingLeft: inset.left + horizontalPadding,
            paddingRight: inset.right + horizontalPadding,
          },
        ]}
        behavior="padding"
      >
        <View
          style={[s.sheet, compact && s.sheetCompact]}
          accessibilityViewIsModal
        >
          <Text style={[s.title, compact && s.titleCompact]}>
            Tag debug settings
          </Text>
          <ScrollView
            testID="debug.settings.fields"
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={s.fields}
            style={s.scroll}
            keyboardDismissMode="interactive"
          >
            <Text style={s.description}>
              Applied to all tags and saved on this device. Correct tag width is
              required for a meaningful pose.
            </Text>
            <View style={s.toggleRow}>
              <View style={s.toggleText}>
                <Text style={s.label}>Show pose axes</Text>
                <Text style={s.hint}>
                  Tag coordinates: red X, green Y, blue Z.
                </Text>
              </View>
              <Switch
                accessibilityLabel="Show pose axes"
                value={showPoseAxes}
                onValueChange={setShowPoseAxes}
                disabled={saving}
              />
            </View>
            <View style={s.toggleRow}>
              <View style={s.toggleText}>
                <Text style={s.label}>Show English units</Text>
                <Text style={s.hint}>
                  Add feet and inches after heights and camera ranges in
                  centimeters.
                </Text>
              </View>
              <Switch
                accessibilityLabel="Show English units"
                value={showImperialHeight}
                onValueChange={setShowImperialHeight}
                disabled={saving}
              />
            </View>
            <View style={s.toggleRow}>
              <View style={s.toggleText}>
                <Text style={s.label}>Level floor with gravity</Text>
                <Text style={s.hint}>
                  Use a horizontal floor at the selected floor's center height.
                  The detected tilt stays visible. Existing measurements keep
                  their original floor.
                </Text>
              </View>
              <Switch
                accessibilityLabel="Level floor with gravity"
                value={levelFloorWithGravity}
                onValueChange={setLevelFloorWithGravity}
                disabled={saving}
              />
            </View>
            <View style={s.fieldGrid}>
              {fields.map(field => (
                <View
                  key={field.key}
                  style={columns ? s.fieldHalf : s.fieldFull}
                >
                  <Text style={s.label}>{field.label}</Text>
                  <TextInput
                    accessibilityLabel={field.label}
                    value={draft[field.key]}
                    onChangeText={value =>
                      setDraft(previous => ({
                        ...previous,
                        [field.key]: value,
                      }))
                    }
                    keyboardType="decimal-pad"
                    selectTextOnFocus
                    style={s.input}
                  />
                  <Text style={s.hint}>{field.hint}</Text>
                  {field.key === 'tagSizeMeters' && (
                    <Pressable
                      accessibilityRole="button"
                      accessibilityLabel="Measure tag width with AR"
                      onPress={onMeasure}
                      disabled={saving}
                      style={s.measure}
                    >
                      <Text style={s.link}>Measure tag width with AR</Text>
                      <Text style={s.hint}>
                        Tap two corners of one tag edge, review the estimate,
                        then apply it.
                      </Text>
                    </Pressable>
                  )}
                </View>
              ))}
            </View>
            <Pressable
              accessibilityRole="button"
              accessibilityLabel="Reset debug settings to FRC defaults"
              onPress={() => {
                setDraft(makeDraft(DEFAULT_DEBUG_SETTINGS));
                setResetToDefaults(true);
                setShowPoseAxes(false);
                setShowImperialHeight(true);
                setLevelFloorWithGravity(false);
              }}
              disabled={saving}
            >
              <Text style={s.link}>Reset to FRC defaults</Text>
            </Pressable>
          </ScrollView>
          <View style={s.actions}>
            <Pressable
              accessibilityRole="button"
              onPress={onCancel}
              disabled={saving}
            >
              <Text style={s.cancel}>Cancel</Text>
            </Pressable>
            <Pressable
              onPress={save}
              disabled={saving}
              style={s.apply}
              accessibilityRole="button"
              accessibilityLabel="Apply debug settings"
            >
              <Text style={s.applyText}>
                {saving ? 'Saving…' : 'Apply settings'}
              </Text>
            </Pressable>
          </View>
        </View>
      </KeyboardAvoidingView>
    </Modal>
  );
}

const s = StyleSheet.create({
  toggleRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    paddingBottom: 16,
    borderBottomColor: '#24415A',
    borderBottomWidth: 1,
  },
  toggleText: { flex: 1 },
  backdrop: {
    flex: 1,
    justifyContent: 'center',
    backgroundColor: '#000000AA',
    alignItems: 'center',
  },
  sheet: {
    backgroundColor: '#102239',
    borderRadius: 20,
    padding: 20,
    width: '100%',
    maxWidth: 900,
    flex: 1,
    maxHeight: 860,
    minHeight: 0,
  },
  sheetCompact: { paddingVertical: 12 },
  titleCompact: { fontSize: 19 },
  title: { color: '#F3F8FD', fontWeight: '700', fontSize: 22 },
  description: {
    color: '#A6BACD',
    fontSize: 12,
    lineHeight: 18,
    marginTop: 0,
  },
  scroll: { flex: 1, minHeight: 0, marginTop: 12 },
  fields: { gap: 16, paddingBottom: 20 },
  fieldGrid: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    justifyContent: 'space-between',
    rowGap: 18,
  },
  fieldFull: { width: '100%' },
  fieldHalf: { width: '48%' },
  label: { color: '#F3F8FD', fontWeight: '600', fontSize: 14 },
  input: {
    color: '#F3F8FD',
    borderColor: '#46627B',
    borderWidth: 1,
    borderRadius: 9,
    paddingHorizontal: 12,
    height: 43,
    fontSize: 18,
    marginVertical: 6,
  },
  hint: { color: '#A6BACD', fontSize: 11, lineHeight: 16 },
  link: { color: '#27E4EF', fontSize: 13, marginTop: 5 },
  measure: {
    borderColor: '#46627B',
    borderWidth: 1,
    borderRadius: 10,
    padding: 12,
    gap: 5,
    marginTop: 10,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingTop: 10,
    borderTopWidth: 1,
    borderTopColor: '#24415A',
    gap: 16,
  },
  cancel: { color: '#A6BACD', fontSize: 14, paddingVertical: 12 },
  apply: {
    backgroundColor: '#27E4EF',
    borderRadius: 10,
    paddingVertical: 12,
    paddingHorizontal: 16,
  },
  applyText: { color: '#071426', fontSize: 14, fontWeight: '700' },
});
