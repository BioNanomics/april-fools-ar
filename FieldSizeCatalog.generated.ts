// Generated from fields/size-standards.yaml. Run generate_sizes.rb after editing YAML.
export const FRC_REFERENCE_SIZE_METERS = 0.1651;
export const FIELD_SEASONS: Record<
  'ftc' | 'frc',
  {
    year: number;
    game: string;
    referenceSizeMeters: number;
    sizeDescription: string;
  }[]
> = {
  ftc: [
    {
      year: 2027,
      game: 'BIOBUZZ',
      referenceSizeMeters: 0.08255,
      sizeDescription: '3.25-inch tags (82.55 mm).',
    },
    {
      year: 2026,
      game: 'DECODE',
      referenceSizeMeters: 0.1651,
      sizeDescription: '6.5-inch tags (165.1 mm).',
    },
    {
      year: 2025,
      game: 'INTO THE DEEP',
      referenceSizeMeters: 0.1016,
      sizeDescription: '4-inch tags (101.6 mm).',
    },
    {
      year: 2024,
      game: 'CENTERSTAGE',
      referenceSizeMeters: 0.0508,
      sizeDescription:
        '2- and 5-inch tags (50.8 and 127 mm). Each tag ID uses its season size.',
    },
  ],
  frc: [
    {
      year: 2026,
      game: 'REBUILT',
      referenceSizeMeters: 0.1651,
      sizeDescription: '6.5-inch tags (165.1 mm).',
    },
    {
      year: 2025,
      game: 'REEFSCAPE',
      referenceSizeMeters: 0.1651,
      sizeDescription: '6.5-inch tags (165.1 mm).',
    },
    {
      year: 2024,
      game: 'CRESCENDO',
      referenceSizeMeters: 0.1651,
      sizeDescription: '6.5-inch tags (165.1 mm).',
    },
  ],
};
