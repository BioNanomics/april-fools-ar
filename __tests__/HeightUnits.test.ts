import { formatHeight } from '../HeightUnits';

test('height display uses one decimal centimeter and optional one decimal feet/inches', () => {
  expect(formatHeight(1.42)).toBe('142.0 cm (4 ft 7.9 in)');
  expect(formatHeight(1.42, false)).toBe('142.0 cm');
  expect(formatHeight(0)).toBe('0.0 cm (0 ft 0.0 in)');
  expect(formatHeight(0, false)).toBe('0.0 cm');
});

test('rounding carries twelve inches into the next foot without changing metric precision', () => {
  expect(formatHeight(11.94 * 0.0254)).toBe('30.3 cm (0 ft 11.9 in)');
  expect(formatHeight(11.96 * 0.0254)).toBe('30.4 cm (1 ft 0.0 in)');
  expect(formatHeight(0.3048)).toBe('30.5 cm (1 ft 0.0 in)');
  expect(formatHeight(59.96 * 0.0254)).toBe('152.3 cm (5 ft 0.0 in)');
});

test('unavailable or invalid heights never become a fabricated zero', () => {
  for (const value of [
    undefined,
    NaN,
    Infinity,
    -Infinity,
    -0.001,
    Number.MAX_VALUE,
  ]) {
    expect(formatHeight(value)).toBe('—');
    expect(formatHeight(value, false)).toBe('—');
  }
});
