# DevNotch — website

The marketing and download site. Static Astro; separate from the app, which it
only reads facts from.

```sh
npm install
npm run dev      # http://localhost:4321
npm run check    # astro check — types and template diagnostics
npm run build    # -> dist/
```

## Where things live

```
src/
  config/site.ts          every product fact, URL, integration, feature and FAQ
  layouts/Base.astro      <head>, SEO, Open Graph
  components/
    NotchDemo.astro       the interactive product demo (used twice)
    Nav · Hero · FeatureGrid · Integrations · HowItWorks
    Download · Faq · OpenSource · Footer
  styles/global.css       tokens, type scale, buttons
public/favicon.svg
```

## Changing content

**`src/config/site.ts` is the only file to edit** for product facts. No
component hard-codes a name, URL, version, integration or FAQ answer.

Publishing a release means changing one entry:

```ts
{
  id: 'macos',
  url: 'https://github.com/.../releases/download/v1.0.0/DevNotch.dmg',
  available: true,        // swaps the disabled state for a real download button
  ...
}
```

`available` controls whether there is a build to download. `supported` controls
whether the app runs on that platform at all — Windows is `supported: false`
because the notch and menu-bar item are AppKit, and no component should imply
otherwise. When nothing is available, the download section renders the
build-from-source block instead, automatically.

## Design notes

The visual system was extracted from [tryalcove.com](https://tryalcove.com) as a
public reference — a Mac notch utility in the same category — then drifted onto
DevNotch's own identity. What was taken is **structure**, not pixels:

- **Demo-led, not text-led.** The product is shown working in the fold and
  again in "How it works", rather than described.
- **Terse two-word feature labels** across an 8-tile bento grid; the drawn art
  carries the explanation.
- **`system-ui`, no webfont.** The reference does this and so does the app —
  it renders in `.AppleSystemUIFont`. It is why the page reads as a Mac app.
- **Warm paper, dark product tiles.** The notch is a dark object; giving it
  dark tiles on warm off-white is what makes it read.

What was *not* taken: the reference's orange accent. DevNotch uses its own
quota colours from `AppPalette.light` — `#059669` / `#8a9908` / `#d84a16` — and
the dark-tile variants from `AppPalette.dark`. Those mean "how close to the
limit" and are never used decoratively.

## Rules this site is built to

- **Nothing stated that the app does not do.** Integration names, taglines and
  accent colours are transcribed from `lib/providers/provider_catalog.dart`;
  the palette and notch metrics from `lib/ui/theme/app_theme.dart` and
  `macos/Runner/RailMetrics.swift`. FAQ answers come from the app's README.
- **No dead links.** A platform without a URL renders as an inert `<span>`,
  never as a link that goes nowhere.
- **The notch is drawn, not photographed.** `NotchDemo.astro` reproduces it at
  the app's own measurements (46 wide, 66 per slot, 32px ring at 2.8 stroke,
  218px card with a 12×18 tail), so it stays accurate without a screenshot to
  keep up to date.
- **Verified, not assumed.** Every text node clears WCAG AA; no horizontal
  overflow at 360 / 390 / 480 / 768 / 1024 / 1280 / 1440 / 1920.

## Notes

- `--ink-3` and `--on-dark-3` are set where they are because anything lighter
  fails AA on this paper. Some of what they carry (platform support, release
  status) is information, not decoration.
- One inline script, for the notch demo. Everything else is static HTML + CSS.
  Total build is ~84 KB.
- The repo is still named `Flux` (the app's earlier name); `GITHUB` in
  `site.ts` is the single place that URL is written.
