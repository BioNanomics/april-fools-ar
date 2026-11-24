import React, { useEffect, useRef, useState } from 'react';
import {
  ActivityIndicator,
  Keyboard,
  Modal,
  Pressable,
  ScrollView,
  Share,
  StyleSheet,
  Text,
  TextInput,
  View,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';

export type FieldPackage = {
  id: string;
  label: string;
  program?: string;
  season?: string;
  variant?: string;
  tagCount?: number;
};
export type FieldTag = {
  id: number;
  family?: string;
  name?: string;
  count?: number;
  acceptedCount?: number;
  rejectedCount?: number;
  frameId?: string;
  segmentId?: string;
  timestamp?: number;
  firstSeen?: number;
  lastSeen?: number;
  videoTimeSeconds?: number | null;
  nominalPosition?: number[] | null;
  observedPosition?: number[] | null;
  observedWorldPosition?: number[] | null;
  expected?: boolean;
  status?: 'seen' | 'notSeen';
  quality?: { usable?: boolean; status?: string; tracking?: string };
  latestObservation?: {
    detection?: Record<string, unknown>;
    source?: Record<string, unknown>;
  };
  latestUsableObservation?: {
    frameId?: string;
    segmentId?: string;
    timestamp?: number;
    observedWorldPosition?: number[] | null;
    observedPosition?: number[] | null;
    detection?: Record<string, unknown>;
    source?: Record<string, unknown>;
  };
  expectedHeightMeters?: number | null;
  observedHeightMeters?: number | null;
  expectedTiltDegrees?: number | null;
  observedTiltDegrees?: number | null;
  reason?: string;
};
type FieldCheck = {
  expected?: number | null;
  observed?: number | null;
  tolerance?: number | null;
  difference?: number | null;
  status?: string;
  reason?: string;
};
export type FieldStatus = {
  packageId?: string | null;
  label?: string;
  packageHash?: string;
  packageSha256?: string;
  coordinateFrame?: string;
  alignment?: string;
  reason?: string;
  anchorId?: number | null;
  candidateId?: number | null;
  checks?: { height?: FieldCheck; tilt?: FieldCheck; gravity?: FieldCheck };
  warnings?: string[];
  seenTags?: FieldTag[];
  seenCount?: number;
  expectedCount?: number;
  expectedSeenCount?: number;
  notSeenTags?: FieldTag[];
  notSeenCount?: number;
  discoveredCount?: number;
  summaryTruncated?: boolean;
  historyOmittedCount?: number;
  inventoryCapacity?: {
    usedEntries: number;
    limitEntries: number;
    observationCount?: number;
  };
  yaml?: string;
  json?: string;
  csv?: string;
};
export type FieldEngine = {
  getFieldCatalog: () => Promise<{
    packages: FieldPackage[];
    error?: string | null;
  }>;
  getFieldDefinition: (id: string) => Promise<{ id: string; yaml: string }>;
  selectField: (id: string) => Promise<FieldStatus>;
  importFieldDefinition: (text: string) => Promise<FieldStatus>;
  getFieldWalk: () => Promise<FieldStatus>;
  getSavedFieldWalk: (id: string) => Promise<{
    yaml: string;
    field?: FieldStatus;
    recordingMode?: 'video' | 'facts';
  }>;
  exportFieldWalk: (
    id: string,
  ) => Promise<{ url: string; path: string; bytes: number }>;
  clearFieldAlignment: () => Promise<FieldStatus>;
  recheckFieldAlignment: () => Promise<FieldStatus>;
  alignFieldUnverified: () => Promise<FieldStatus>;
};

type Props = {
  visible: boolean;
  engine?: Partial<FieldEngine>;
  recording?: boolean;
  field?: FieldStatus;
  savedSession?: {
    id: string;
    name: string;
    recordingMode?: 'video' | 'facts';
  } | null;
  onClose: () => void;
  onDismiss?: () => void;
  onChange?: (field: FieldStatus) => void;
  onSetFloor?: () => void;
  onOpenEvidence?: (tag: FieldTag) => void;
};
type Page = 'walk' | 'fields' | 'yaml' | 'import';
const colors = {
  bg: '#071426',
  card: '#102239',
  line: '#24415A',
  text: '#F3F8FD',
  muted: '#A6BACD',
  accent: '#A1D18B',
  warning: '#FFCB7A',
};
const finite = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);
const numberText = (value: unknown, scale = 1, digits = 1) =>
  finite(value) ? (value * scale).toFixed(digits) : 'unavailable';
const positionText = (point?: number[] | null) =>
  point?.length === 3 && point.every(finite)
    ? `${point.map(value => value.toFixed(3)).join(', ')} m`
    : 'unavailable';
const errorText = (error: unknown) =>
  error instanceof Error ? error.message : String(error);

function Action({
  label,
  onPress,
  disabled = false,
  selected = false,
}: {
  label: string;
  onPress: () => void;
  disabled?: boolean;
  selected?: boolean;
}) {
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={label}
      accessibilityState={{ disabled, selected }}
      disabled={disabled}
      onPress={onPress}
      style={[s.action, selected && s.selected, disabled && s.disabled]}
    >
      <Text style={[s.actionText, selected && s.selectedText]}>{label}</Text>
    </Pressable>
  );
}

function CheckReadout({
  label,
  check,
  scale = 1,
  unit,
}: {
  label: string;
  check?: FieldCheck;
  scale?: number;
  unit: string;
}) {
  if (!check) {
    return null;
  }
  return (
    <Text style={s.detail} accessibilityLabel={`${label} comparison`}>
      {label}:{' '}
      {!finite(check.expected) &&
      !finite(check.observed) &&
      finite(check.difference)
        ? `difference ${numberText(check.difference, scale)} ${unit}`
        : `expected ${numberText(
            check.expected,
            scale,
          )} ${unit}, observed ${numberText(check.observed, scale)} ${unit}`}
      {finite(check.expected) && finite(check.observed)
        ? ` · Δ ${numberText(check.observed - check.expected, scale)} ${unit}`
        : ''}
      {finite(check.tolerance)
        ? ` · allowed ±${numberText(check.tolerance, scale)} ${unit}`
        : ''}
      {check.status ? ` · ${check.status}` : ''}
      {check.reason ? ` · ${check.reason}` : ''}
    </Text>
  );
}

export function FieldDefinitionsPanel({
  visible,
  engine,
  recording = false,
  field,
  savedSession,
  onClose,
  onDismiss,
  onChange,
  onSetFloor,
  onOpenEvidence,
}: Props) {
  const [page, setPage] = useState<Page>('walk');
  const [packages, setPackages] = useState<FieldPackage[]>([]);
  const [draftId, setDraftId] = useState<string | null>(null);
  const [walk, setWalk] = useState<FieldStatus>(field || {});
  const [yaml, setYaml] = useState('');
  const [importText, setImportText] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [savedMode, setSavedMode] = useState<'video' | 'facts' | undefined>(
    savedSession?.recordingMode,
  );
  const generation = useRef(0);
  const saved = Boolean(savedSession);
  useEffect(() => {
    if (visible && !saved) {
      setWalk(field || {});
    }
  }, [visible, field, saved]);
  useEffect(() => {
    const request = ++generation.current;
    let active = true;
    if (!visible) {
      return;
    }
    setError('');
    setImportText('');
    setYaml('');
    setBusy(true);
    setDraftId(field?.packageId || null);
    setPage(savedSession ? 'walk' : field?.packageId ? 'walk' : 'fields');
    const load = async () => {
      if (savedSession) {
        if (!engine?.getSavedFieldWalk) {
          throw new Error('Saved field data is unavailable in this build.');
        }
        const result = await engine.getSavedFieldWalk(savedSession.id);
        if (!active || generation.current !== request) {
          return;
        }
        setWalk(result.field || {});
        setYaml(result.yaml || '');
        setSavedMode(result.recordingMode || savedSession.recordingMode);
      } else {
        if (!engine?.getFieldCatalog || !engine.getFieldWalk) {
          throw new Error('Field definitions are unavailable in this build.');
        }
        const [catalog, current] = await Promise.all([
          engine.getFieldCatalog(),
          engine.getFieldWalk(),
        ]);
        if (!active || generation.current !== request) {
          return;
        }
        if (catalog.error && !catalog.packages?.length) {
          throw new Error(catalog.error);
        }
        setPackages(catalog.packages || []);
        setWalk(current);
        setDraftId(current.packageId || null);
      }
    };
    load()
      .catch(e => {
        if (active && generation.current === request) {
          setError(errorText(e));
        }
      })
      .finally(() => {
        if (active && generation.current === request) {
          setBusy(false);
        }
      });
    return () => {
      active = false;
    };
    // A native status update must not reset the operator's draft catalog choice.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible, engine, savedSession?.id]);

  if (!visible) {
    // Retain the same native Modal while it dismisses. The parent waits for
    // onDismiss before presenting a recorded-time evidence player.
    return <Modal visible={false} onDismiss={onDismiss} />;
  }
  const perform = async (operation: () => Promise<void>) => {
    if (busy) {
      return;
    }
    setBusy(true);
    setError('');
    try {
      await operation();
    } catch (e) {
      setError(errorText(e));
    } finally {
      setBusy(false);
    }
  };
  const update = (next: FieldStatus) => {
    setWalk(next);
    onChange?.(next);
  };
  const showYaml = () =>
    perform(async () => {
      if (saved) {
        setPage('yaml');
        return;
      }
      const id = draftId || walk.packageId;
      if (!id) {
        throw new Error('Choose a field definition first.');
      }
      if (!engine?.getFieldDefinition) {
        throw new Error('Definition viewer unavailable.');
      }
      const result = await engine.getFieldDefinition(id);
      setYaml(result.yaml);
      setPage('yaml');
    });
  const apply = () =>
    perform(async () => {
      if (recording) {
        throw new Error('Stop and save the walk before changing its field.');
      }
      if (!draftId || !engine?.selectField) {
        throw new Error('Choose an available field definition.');
      }
      update(await engine.selectField(draftId));
      setPage('walk');
    });
  const importDefinition = () =>
    perform(async () => {
      if (recording) {
        throw new Error('Stop and save the walk before importing a field.');
      }
      if (!importText.trim() || !engine?.importFieldDefinition) {
        throw new Error('Paste a YAML or JSON field definition.');
      }
      const next = await engine.importFieldDefinition(importText);
      update(next);
      setDraftId(next.packageId || null);
      setPage('walk');
      if (engine.getFieldCatalog) {
        setPackages((await engine.getFieldCatalog()).packages);
      }
    });
  const share = (format: 'yaml' | 'json' | 'csv') =>
    perform(async () => {
      if (format === 'yaml' && savedSession) {
        if (!engine?.exportFieldWalk) {
          throw new Error('YAML file export is unavailable in this build.');
        }
        const file = await engine.exportFieldWalk(savedSession.id);
        if (!file.url) {
          throw new Error('The saved YAML file is unavailable.');
        }
        await Share.share({
          url: file.url,
          title: `${savedSession.name} · YAML`,
        });
        return;
      }
      const data = saved ? walk : (await engine?.getFieldWalk?.()) || walk;
      const message =
        format === 'yaml'
          ? saved
            ? yaml
            : data.yaml
          : format === 'json'
          ? data.json || JSON.stringify(data, null, 2)
          : data.csv ||
            [
              'id,family,count,nominal_x,nominal_y,nominal_z',
              ...(data.seenTags || []).map(tag =>
                [
                  tag.id,
                  tag.family || 'tag36h11',
                  tag.count || 0,
                  ...(tag.nominalPosition || ['', '', '']),
                ].join(','),
              ),
            ].join('\n');
      if (!message) {
        throw new Error('There is no saved field summary to share yet.');
      }
      await Share.share({
        message,
        title: `${
          savedSession?.name || 'Field walk'
        } · ${format.toUpperCase()}`,
      });
    });
  const command = (
    name:
      | 'recheckFieldAlignment'
      | 'clearFieldAlignment'
      | 'alignFieldUnverified',
  ) =>
    perform(async () => {
      const fn = engine?.[name];
      if (!fn) {
        throw new Error('Alignment control unavailable.');
      }
      update(await fn());
    });
  const checks = walk.checks;
  const failedCheck = [checks?.height, checks?.tilt, checks?.gravity].some(
    check => check?.status === 'failed' || check?.status === 'fail',
  );
  const canAlignUnverified =
    walk.candidateId != null &&
    ['unavailable', 'unverified'].includes(checks?.height?.status || '') &&
    [checks?.tilt, checks?.gravity].every(check =>
      ['passed', 'pass'].includes(check?.status || ''),
    ) &&
    !failedCheck;
  const packageHash = walk.packageSha256 || walk.packageHash;
  const tags = walk.seenTags || [];

  return (
    <Modal
      visible
      transparent
      animationType="slide"
      onRequestClose={onClose}
      onDismiss={onDismiss}
      supportedOrientations={[
        'portrait',
        'landscape-left',
        'landscape-right',
        'portrait-upside-down',
      ]}
    >
      <SafeAreaView style={s.backdrop} accessibilityViewIsModal>
        <View style={s.sheet}>
          <View style={s.header}>
            <Text style={s.title} accessibilityRole="header">
              {savedSession
                ? `Field walk · ${savedSession.name}`
                : 'Field & tags'}
            </Text>
            {page === 'import' && (
              <Action label="Hide keyboard" onPress={Keyboard.dismiss} />
            )}
            <Action label="Close field definitions" onPress={onClose} />
          </View>
          <View style={s.actions}>
            <Action
              label="Tags seen"
              onPress={() => setPage('walk')}
              selected={page === 'walk'}
            />
            {!saved && (
              <Action
                label="Choose field"
                onPress={() => setPage('fields')}
                selected={page === 'fields'}
              />
            )}
            <Action
              label="View YAML"
              onPress={showYaml}
              disabled={busy}
              selected={page === 'yaml'}
            />
            {!saved && (
              <Action
                label="Import YAML or JSON"
                onPress={() => setPage('import')}
                selected={page === 'import'}
                disabled={recording}
              />
            )}
          </View>
          <ScrollView
            style={s.scroll}
            contentContainerStyle={s.content}
            automaticallyAdjustKeyboardInsets
            keyboardDismissMode="on-drag"
            keyboardShouldPersistTaps="handled"
          >
            {busy && (
              <ActivityIndicator
                color={colors.accent}
                accessibilityLabel="Loading field data"
              />
            )}
            {!!error && (
              <Text accessibilityRole="alert" style={s.warning}>
                {error}
              </Text>
            )}
            {recording && !saved && (
              <Text style={s.note}>
                Field definition pinned to this recording. Stop and save to
                change it.
              </Text>
            )}
            {page === 'fields' && (
              <>
                <Text style={s.heading}>Competition field</Text>
                <Text style={s.detail}>
                  Choose the full season and field variant. Auto tag width does
                  not select a field.
                </Text>
                {packages.map(item => (
                  <Pressable
                    key={item.id}
                    accessibilityRole="radio"
                    accessibilityLabel={`Select ${item.label}`}
                    accessibilityState={{
                      checked: draftId === item.id,
                      disabled: recording || busy,
                    }}
                    disabled={recording || busy}
                    onPress={() => setDraftId(item.id)}
                    style={[s.card, draftId === item.id && s.selectedCard]}
                  >
                    <Text style={s.heading}>
                      {draftId === item.id ? '● ' : '○ '}
                      {item.label}
                    </Text>
                    <Text style={s.detail}>
                      {[item.program, item.season, item.variant]
                        .filter(Boolean)
                        .join(' · ')}
                      {item.tagCount != null ? ` · ${item.tagCount} tags` : ''}
                    </Text>
                  </Pressable>
                ))}
                {!packages.length && !busy && (
                  <Text style={s.detail}>No field definitions available.</Text>
                )}
                <View style={s.actions}>
                  <Action
                    label="Use selected field"
                    onPress={apply}
                    disabled={busy || recording || !draftId}
                  />
                  <Action
                    label="Cancel field selection"
                    onPress={() => {
                      setDraftId(walk.packageId || null);
                      onClose();
                    }}
                  />
                </View>
              </>
            )}
            {page === 'walk' && (
              <>
                <Text style={s.heading}>
                  {walk.label || 'No field selected'}
                </Text>
                {!!packageHash && (
                  <Text selectable style={s.identifier}>
                    Package {packageHash}
                  </Text>
                )}
                <Text style={s.detail}>
                  XYZ field frame: {walk.coordinateFrame || 'unavailable'}
                </Text>
                <Text style={s.alignment} accessibilityLiveRegion="polite">
                  Alignment: {walk.alignment || 'unaligned'}
                  {walk.anchorId != null ? ` · anchor #${walk.anchorId}` : ''}
                </Text>
                {!!walk.reason && <Text style={s.note}>{walk.reason}</Text>}
                <CheckReadout
                  label="Center height"
                  check={checks?.height}
                  scale={100}
                  unit="cm"
                />
                <CheckReadout
                  label="Tilt from vertical"
                  check={checks?.tilt}
                  unit="°"
                />
                <CheckReadout
                  label="Gravity orientation"
                  check={checks?.gravity}
                  unit="°"
                />
                {!!walk.warnings?.length && (
                  <Text style={s.heading}>Recorded warnings</Text>
                )}
                {(walk.warnings || []).map((warning, i) => (
                  <Text
                    key={`${i}:${warning}`}
                    accessibilityRole="alert"
                    style={s.warning}
                  >
                    {warning}
                  </Text>
                ))}
                {!saved && (
                  <View style={s.actions}>
                    <Action
                      label="Recheck field alignment"
                      onPress={() => command('recheckFieldAlignment')}
                      disabled={busy || !walk.packageId}
                    />
                    <Action
                      label="Clear field alignment"
                      onPress={() => command('clearFieldAlignment')}
                      disabled={busy}
                    />
                    {!!onSetFloor && (
                      <Action
                        label="Set floor for anchor height"
                        onPress={onSetFloor}
                      />
                    )}
                    {canAlignUnverified && (
                      <Action
                        label="Align without height check"
                        onPress={() => command('alignFieldUnverified')}
                        disabled={busy || !walk.packageId}
                      />
                    )}
                  </View>
                )}
                <Text style={s.heading}>
                  Tags seen: {walk.seenCount ?? tags.length}
                  {walk.expectedCount != null && walk.expectedCount > 0
                    ? ` · ${
                        walk.expectedSeenCount ?? walk.seenCount ?? tags.length
                      } / ${walk.expectedCount} expected`
                    : ''}
                </Text>
                {saved && savedMode === 'facts' && (
                  <Text style={s.note}>
                    Walk facts saved as YAML. This session has no video or
                    sensor playback.
                  </Text>
                )}
                {walk.discoveredCount != null && walk.discoveredCount > 0 && (
                  <Text style={s.detail}>
                    {walk.packageId
                      ? 'Discovered outside the selected definition: '
                      : 'Discovered tags: '}
                    {walk.discoveredCount}
                  </Text>
                )}
                {!walk.packageId && (
                  <Text style={s.note}>
                    {saved
                      ? 'No field definition was selected for this walk. Expected tags not seen are unavailable.'
                      : 'Choose a field definition to include expected tags not seen in the walk summary.'}
                  </Text>
                )}
                {walk.summaryTruncated && (
                  <Text style={s.warning}>
                    The summary reached its retained evidence capacity. Counts
                    and available facts are retained; some tag observations or
                    older registration events were omitted.
                  </Text>
                )}
                {!tags.length && (
                  <Text style={s.detail}>
                    {saved
                      ? 'No tag observations are saved in this walk.'
                      : 'Start recording and walk past tags to build the saved list. Preview sightings are separate.'}
                  </Text>
                )}
                {tags.map(tag => (
                  <View key={`${tag.family || ''}:${tag.id}`} style={s.card}>
                    <Text style={s.heading}>
                      #{tag.id}
                      {tag.name ? ` · ${tag.name}` : ''}
                    </Text>
                    <Text style={s.detail}>
                      {tag.family || 'tag36h11'} · {tag.count ?? 0} observations
                      {tag.acceptedCount != null
                        ? ` · ${tag.acceptedCount} accepted`
                        : ''}
                      {tag.rejectedCount != null
                        ? ` · ${tag.rejectedCount} rejected`
                        : ''}
                    </Text>
                    <Text selectable style={s.detail}>
                      Published XYZ: {positionText(tag.nominalPosition)}
                    </Text>
                    <Text selectable style={s.detail}>
                      Observed XYZ: {positionText(tag.observedPosition)}
                    </Text>
                    {tag.expected === false && (
                      <Text style={s.note}>
                        Discovered tag · no published position in the selected
                        definition.
                      </Text>
                    )}
                    {tag.observedWorldPosition && (
                      <Text selectable style={s.detail}>
                        Local AR XYZ: {positionText(tag.observedWorldPosition)}{' '}
                        · segment {tag.segmentId || 'unavailable'} · Y up
                      </Text>
                    )}
                    {tag.quality?.usable === false &&
                      tag.latestUsableObservation && (
                        <Text selectable style={s.detail}>
                          Latest usable position:{' '}
                          {positionText(
                            tag.latestUsableObservation.observedPosition ||
                              tag.latestUsableObservation.observedWorldPosition,
                          )}
                          {tag.latestUsableObservation.observedPosition
                            ? ' · field frame'
                            : ' · local AR frame, Y up'}
                          {' · segment '}
                          {tag.latestUsableObservation.segmentId ||
                            'unavailable'}
                          {' · source frame '}
                          {tag.latestUsableObservation.frameId || 'unavailable'}
                        </Text>
                      )}
                    {(tag.expectedHeightMeters != null ||
                      tag.observedHeightMeters != null) && (
                      <Text style={s.detail}>
                        Height: expected{' '}
                        {numberText(tag.expectedHeightMeters, 100)} cm ·
                        observed {numberText(tag.observedHeightMeters, 100)} cm
                      </Text>
                    )}
                    {(tag.expectedTiltDegrees != null ||
                      tag.observedTiltDegrees != null) && (
                      <Text style={s.detail}>
                        Tilt: expected {numberText(tag.expectedTiltDegrees)}° ·
                        observed {numberText(tag.observedTiltDegrees)}°
                      </Text>
                    )}
                    {!!tag.reason && <Text style={s.note}>{tag.reason}</Text>}
                    {!!tag.frameId && (
                      <Text selectable style={s.note}>
                        Source frame: {tag.frameId}
                        {tag.segmentId ? ` · segment ${tag.segmentId}` : ''}
                        {finite(tag.timestamp)
                          ? ` · source time ${tag.timestamp} s`
                          : ''}
                      </Text>
                    )}
                    {saved &&
                      savedMode !== 'facts' &&
                      (onOpenEvidence &&
                      finite(tag.videoTimeSeconds) &&
                      tag.videoTimeSeconds >= 0 ? (
                        <>
                          <Action
                            label={`Open observation for tag ${tag.id}`}
                            onPress={() => onOpenEvidence(tag)}
                          />
                          <Text style={s.note}>
                            Opens the video at the recorded observation time;
                            the source frame may be metadata only.
                          </Text>
                        </>
                      ) : (
                        <Text style={s.note}>
                          Recorded-time video link unavailable for this
                          observation.
                        </Text>
                      ))}
                  </View>
                ))}
                {!!walk.notSeenTags?.length && (
                  <>
                    <Text style={s.heading}>
                      Expected but not seen:{' '}
                      {walk.notSeenCount ?? walk.notSeenTags.length}
                    </Text>
                    <Text style={s.note}>
                      These tags were not observed in this walk. This does not
                      establish that they are physically missing.
                    </Text>
                    {walk.notSeenTags.map(tag => (
                      <View
                        key={`notSeen:${tag.family || ''}:${tag.id}`}
                        style={s.card}
                      >
                        <Text style={s.heading}>
                          #{tag.id}
                          {tag.name ? ` · ${tag.name}` : ''} · not seen
                        </Text>
                        <Text selectable style={s.detail}>
                          Published XYZ: {positionText(tag.nominalPosition)}
                        </Text>
                      </View>
                    ))}
                  </>
                )}
                <View style={s.actions}>
                  <Action
                    label="Share walk YAML"
                    onPress={() => share('yaml')}
                    disabled={busy}
                  />
                  <Action
                    label="Share walk JSON"
                    onPress={() => share('json')}
                    disabled={busy}
                  />
                  <Action
                    label="Share walk CSV"
                    onPress={() => share('csv')}
                    disabled={busy}
                  />
                </View>
              </>
            )}
            {page === 'yaml' && (
              <>
                <Text style={s.heading}>
                  {saved ? 'Saved walk YAML' : 'Field definition YAML'}
                </Text>
                <Text
                  selectable
                  style={s.yaml}
                  accessibilityLabel="Field YAML document"
                  accessibilityValue={{
                    text: yaml || 'No YAML document available.',
                  }}
                >
                  {yaml || 'No YAML document available.'}
                </Text>
              </>
            )}
            {page === 'import' && (
              <>
                <Text style={s.heading}>Import a field definition</Text>
                <Text style={s.detail}>
                  Paste YAML or JSON. The validated definition is stored and
                  displayed as YAML.
                </Text>
                <TextInput
                  accessibilityLabel="Field definition YAML or JSON"
                  multiline
                  autoCapitalize="none"
                  autoCorrect={false}
                  value={importText}
                  onChangeText={setImportText}
                  editable={!recording && !busy}
                  style={s.input}
                  placeholder="Paste a field package here…"
                  placeholderTextColor={colors.muted}
                />
                <Action
                  label="Validate and use imported field"
                  onPress={importDefinition}
                  disabled={busy || recording || !importText.trim()}
                />
              </>
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
    backgroundColor: '#020A14DD',
    padding: 12,
    justifyContent: 'center',
  },
  sheet: {
    width: '100%',
    maxWidth: 900,
    maxHeight: '100%',
    alignSelf: 'center',
    backgroundColor: colors.bg,
    borderRadius: 16,
    borderWidth: 1,
    borderColor: colors.line,
    overflow: 'hidden',
  },
  header: {
    padding: 16,
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
    gap: 10,
    justifyContent: 'space-between',
  },
  title: { color: colors.text, fontSize: 20, fontWeight: '700', flexShrink: 1 },
  heading: { color: colors.text, fontSize: 16, fontWeight: '600' },
  actions: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    paddingHorizontal: 12,
    paddingBottom: 10,
  },
  action: {
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 8,
    minHeight: 44,
    justifyContent: 'center',
    paddingHorizontal: 12,
    paddingVertical: 10,
  },
  actionText: { color: colors.accent, fontSize: 13, fontWeight: '600' },
  selected: { backgroundColor: colors.accent },
  selectedText: { color: colors.bg },
  disabled: { opacity: 0.4 },
  scroll: { flexShrink: 1 },
  content: { padding: 16, gap: 12, paddingBottom: 28 },
  card: {
    backgroundColor: colors.card,
    borderWidth: 1,
    borderColor: colors.line,
    padding: 12,
    borderRadius: 8,
    gap: 6,
  },
  selectedCard: { borderColor: colors.accent },
  detail: { color: colors.muted, fontSize: 13, lineHeight: 19 },
  note: { color: colors.warning, fontSize: 13, lineHeight: 19 },
  warning: {
    color: colors.warning,
    fontSize: 14,
    lineHeight: 20,
    backgroundColor: colors.card,
    borderRadius: 8,
    padding: 10,
  },
  alignment: { color: colors.accent, fontSize: 15, fontWeight: '600' },
  identifier: { fontFamily: 'Menlo', fontSize: 10, color: colors.muted },
  yaml: {
    color: colors.text,
    fontFamily: 'Menlo',
    fontSize: 12,
    lineHeight: 18,
  },
  input: {
    minHeight: 220,
    borderWidth: 1,
    borderColor: colors.line,
    borderRadius: 8,
    padding: 12,
    color: colors.text,
    fontFamily: 'Menlo',
    fontSize: 12,
    textAlignVertical: 'top',
  },
});
