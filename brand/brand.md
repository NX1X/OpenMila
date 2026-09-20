<!-- Copyright 2026 NX1X. Licensed under the Apache License, Version 2.0. -->

# OpenMila brand kit

Everything OpenMila shows of itself: the mark, the lockups, the colours, the
type, and the rules for using them. The artwork here is OpenMila's own. It is
not derived from Mila's or Island's artwork, and it must never be used in a way
that suggests Island Technology, Inc. endorses this port.

## What the mark means

The mark is an open ring around a three-bar level meter. The meter is the
product at work: speech, being measured as it is recorded. The ring is the O of
Open, drawn as a stroke with a gap in it rather than as a closed seal, because
the source is there to be read; the bars sit wholly inside it, which is where
the audio stays, on your own machine. The whole thing is built from two
elements only, a circle and three rounded bars, so it still reads at the size of
a browser tab. It borrows nothing from Mila: no microphone silhouette, no
reuse of Mila's icon shape or palette beyond the system accent colour the app
itself uses, and a wordmark drawn from scratch as monoline letterforms that
exist nowhere else.

## Files

| File | Use |
|---|---|
| `mark.svg` | The mark alone, square, safe down to 16px. App icon, avatars, favicons. |
| `mark-small.svg` | The 16px cut of the mark: one bar instead of three, thicker ring. Raster only, used by the renderer below. |
| `logo.svg` | Horizontal lockup: mark plus wordmark. The default. |
| `logo-stacked.svg` | Stacked lockup, for square and narrow spaces. |
| `logo-mono.svg` | Single colour, everything `currentColor`. For one-colour printing, engraving, and anywhere the background is busy. |
| `icons/` | Generated PNG and ICO files (see *Regenerating*). |
| `social-preview.png` | 1280x640, for the GitHub repository's social preview. |
| `tokens.css`, `tokens.json` | The colours and spacing below, for the website and any other consumer. |

The mono lockup drops the blue tile on purpose. A tile cannot be knocked
through in one colour, and the open ring reads on any background without it.

## Colours

The three product colours are the app's own tokens, so the icon and the
interface agree (`Port/App/Sources/Theme/Theme.swift`).

| Token | Hex | Where it is used |
|---|---|---|
| `--om-accent` | `#007AFF` | The brand blue. Links, selected rows, primary buttons, the accent in the app. |
| `--om-accent-soft` | `#3D9BFF` | Top of the icon tile's gradient. Accent text on dark backgrounds, where `#007AFF` is too dim. |
| `--om-accent-strong` | `#0057D8` | Bottom of the icon tile's gradient. Hover and pressed states, accent text on white, where `#007AFF` is too light for body-size text. |
| `--om-recording` | `#FF3B30` | Recording in progress, and nothing else. |
| `--om-danger` | `#FF3B30` | Destructive actions and error states. |
| `--om-success` | `#34C759` | Finished transcriptions, verified settings. |
| `--om-ink` | `#121417` | The wordmark and body text on light backgrounds. |
| `--om-muted` | `#8C8C94` | Secondary text. The app's `Theme.secondaryText`. |
| `--om-canvas-top` | `#0A1729` | Top of the deep background used by the social preview. |
| `--om-canvas-bottom` | `#060C16` | Bottom of the same background. |

Surfaces, borders and text colours have light and dark values; both sets are in
`tokens.css` and `tokens.json`. The speaker palette (`--om-speaker-1` to
`--om-speaker-8`) is the app's `Theme.speakers`, in the same order, so a speaker
keeps their colour between the app, a transcript exported to the web, and any
screenshot in the documentation.

Contrast: `#007AFF` on white is 4.0:1. That passes for large text, buttons and
other non-text elements, and it falls short for body text - use
`--om-accent-strong` there (6.3:1 on white). On the dark surface use
`--om-accent-soft` (6.4:1 on `#14171A`).

## Typography

There is no licensed font anywhere in this kit. The wordmark is drawn, not set,
so it needs no font file at all, and everything around it uses the reader's own
system fonts:

```css
font-family: system-ui, -apple-system, "Segoe UI", Roboto, "Noto Sans",
             "Noto Sans Hebrew", "Helvetica Neue", Arial, sans-serif;
```

```css
font-family: ui-monospace, "Cascadia Mono", "JetBrains Mono", Consolas,
             "DejaVu Sans Mono", "Liberation Mono", monospace;
```

`Noto Sans Hebrew` is in the stack on purpose: OpenMila transcribes Hebrew, and
Hebrew has to render in the interface, in transcripts and in documentation
screenshots without falling back to a default that breaks the line.

Use weight 600 for headings and the interface, 400 for body text, and sentence
case for headings. Never re-set the wordmark in a font: it is artwork, and
`logo.svg` is the only correct "OpenMila".

## Clear space and minimum sizes

Clear space is `x`, one quarter of the mark's height. Keep `x` free of other
graphics and of the edge of the medium on all four sides of any lockup. For the
horizontal lockup, `x` is also roughly the wordmark's cap height, so the rule is
easy to eyeball.

| Artwork | Minimum |
|---|---|
| `mark.svg` | 16px. The 16px raster is drawn from `mark-small.svg`; do not scale the three-bar mark itself below 20px. |
| `logo.svg` | 120px wide. |
| `logo-stacked.svg` | 96px wide. |
| `logo-mono.svg` | 120px wide (horizontal). |

In print, 12mm wide for the lockups and 5mm for the mark.

## What not to do

- Do not recolour the mark. The tile is the blue gradient; the ring and bars
  are white. If the background fights it, use `logo-mono.svg`.
- Do not close the gap in the ring, add a fourth bar, change the bar heights,
  or re-centre the glyph. The proportions are the mark.
- Do not put the coloured mark on a mid-blue background, or on a photograph
  without a plain panel behind it.
- Do not add shadows, glows, bevels, outlines or gradients of your own.
- Do not stretch, squash, rotate or skew any of it.
- Do not set the wordmark in a typeface, letter-space it, or translate it.
  "OpenMila" is one word, capital O, capital M.
- Do not use Mila's name or artwork as though it were OpenMila's, and do not
  place OpenMila's mark beside Island's in a way that implies a partnership.
  OpenMila is an independent community port.
- Do not use the mark for a fork or a rebuild that is not this project's
  release. Apache-2.0 covers the code, not an implied endorsement.

## Regenerating the raster artwork

`render-icons.py` is the only way these files are produced. It reads the SVG
sources in this directory and uses the Python standard library only, so CI needs
nothing beyond `python3`:

```bash
python3 brand/render-icons.py            # rewrites brand/icons/ and brand/social-preview.png
python3 brand/render-icons.py --out DIR  # writes the same set somewhere else
```

It produces:

- `icons/openmila-{16,24,32,48,64,128,256,512}.png` - the Linux hicolor theme
  sizes. `openmila-512.png` is also the website's 512px PNG.
- `icons/openmila.ico` - 16, 32, 48 and 256, for Windows.
- `icons/favicon.ico` - 16, 32 and 48, for the website.
- `social-preview.png` - 1280x640, for the repository's social preview.

The output is committed, so packaging never has to run the renderer. Rerun it
whenever an SVG source changes, and commit what changes.
