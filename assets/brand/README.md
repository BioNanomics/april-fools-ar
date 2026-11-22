# The REFINERY app branding

The source wordmark is The REFINERY's existing full-color vector logo, retrieved
on 2026-11-22 from:

https://refineryrobotics.org/_astro/logo-full-color.w_3JyM_4_22LaGe.svg

`refinery-logo.svg` preserves that source. The transparent PNGs are the same
wordmark rendered at 1× (292 × 76), 2× (584 × 152), and 3× (876 × 228) for React
Native. Display the full-color wordmark on a light background.

`app-icon.svg` uses the exact wrench path and its dark-green details from that
wordmark. A blue camera-viewfinder frame identifies the AR capture app. The
background fills the full square; iOS supplies its own corner mask. The app icon
render is 1024 × 1024, RGB, opaque, with no alpha channel.

Brand colors from the source:

- Green: `#40A578`
- Dark green: `#115A40`
- Blue: `#134B70`
- Supporting icon backgrounds: `#F4F8F6`, `#E6EFEC`, white

The REFINERY and BioNanomics names, wordmark, and derived app icon identify their
organization and app. Their inclusion does not grant trademark rights under the
app's software license.

## Re-rendering

Requires `rsvg-convert` and ImageMagick (`magick`). Run from the repository root:

```sh
rsvg-convert -w 292 -h 76 assets/brand/refinery-logo.svg -o assets/brand/refinery-logo.png
rsvg-convert -w 584 -h 152 assets/brand/refinery-logo.svg -o assets/brand/refinery-logo@2x.png
rsvg-convert -w 876 -h 228 assets/brand/refinery-logo.svg -o assets/brand/refinery-logo@3x.png
rsvg-convert -w 1024 -h 1024 assets/brand/app-icon.svg -o /tmp/refinery-app-icon.png
magick /tmp/refinery-app-icon.png -alpha off -depth 8 ios/AprilFoolsAR/Images.xcassets/AppIcon.appiconset/AppIcon.png
```
