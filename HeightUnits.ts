/** Presentation only: captured geometry and stored heights stay in meters. */
export function formatHeight(
  meters: number | undefined,
  showImperial = true,
): string {
  if (
    meters == null ||
    !Number.isFinite(meters) ||
    meters < 0 ||
    !Number.isFinite(meters * 1000)
  ) {
    return '—';
  }
  const metric = `${(Math.round(meters * 1000) / 10).toFixed(1)} cm`;
  if (!showImperial) {
    return metric;
  }
  // Round once in tenths of an inch, then split. 11.96 in becomes 1 ft 0.0 in.
  const tenths = Math.round((meters / 0.0254) * 10);
  if (!Number.isSafeInteger(tenths)) {
    return '—';
  }
  const feet = Math.floor(tenths / 120);
  const inches = (tenths % 120) / 10;
  return `${metric} (${feet} ft ${inches.toFixed(1)} in)`;
}
