# Linked metric glossary validation

November 24, 2026. Release 0.10.1 (33), based on the current field/year release.

Every metric label in the native expanded Details readout opens its section in
an offline glossary. The page has 33 stable definitions and six accessible SVG
diagrams. `docs/tag-metric-glossary.md` and `docs/diagrams/` are the maintained
sources; the build generates the bundled page and rejects missing images or
broken internal section references.

Links include individual Tilt/Twist terms, pose/depth/geometry headings,
decoder and timing labels, identity/height/source labels, and the Auto,
FTC/FRC, competition-year and width-setting labels. Numeric values keep their
existing formatting and severity colors. Compact/background touches still pass
through, constrained panels scroll, and Done restores the expanded readout.
Rich spoken angle meanings and unavailable reasons remain on the native links.

The isolated release source passed all **23 native simulator tests**: 21 panel
checks and two real WebKit checks. These cover term routing and hit targets,
link accessibility/activation, current field/year sizing, unavailable data,
compact/background touch passthrough, short-landscape layout, view reuse across
600 updates, section deep linking, six local SVGs with alt text, and dismissal.
The panel and glossary screenshots were visually inspected. This verifies native
UI and offline help behavior; it does not establish camera or LiDAR accuracy.

Evidence: `/tmp/april-glossary-release-validation-20261124/Results.xcresult`,
`xcodebuild.log`, and `artifacts/`. The dedicated simulator was shut down after
testing. The source was prepared separately from unrelated pending changes in
the shared working checkout.
