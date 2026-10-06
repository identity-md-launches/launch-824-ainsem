# AINSEM design system

## Overview

A dark, single-page view of the IMD swarm. The dense, full-width tile wall is the visual center; the surrounding page uses large condensed lettering and generous space. Visitors inspect seats, deal a snapshot of 13 enrolled agents, download the card, and open an X draft. The live wall and the explanatory trade flow are the only animated regions.

The implementation is in `web/src/main.tsx`, `web/src/style.css`, `web/src/data.ts`, and `web/src/card.ts`. There is no component framework or theme switch. The published artifact is `dist/`.

## Colors

Canonical hex tokens live at the start of `web/src/style.css`.

| Token | Value | Role |
| --- | --- | --- |
| `--ink` | `#0E0D0B` | Page background, primary-button text, focus backing |
| `--surface` | `#17150F` | Seat input and connection notice |
| `--ivory` | `#EFE7D6` | Body text, tile faces, primary buttons, focus outline |
| `--edge` | `#CDBF9F` | Tile thickness and primary hover |
| `--back` | `#1F3B2E` | Open-seat backs and dark glyphs on ivory |
| `--jade` | `#3FA37A` | AI in the wordmark, links, heartbeat, trade flow |
| `--working` | `#E0322B` | Working tiles (including the legend sample) and live dot only |
| `--muted` | `#8C8573` | Secondary text and labels |
| `--line` | `#38352C` | Structural separators |

Transparent whites create top-left tile bevels; transparent ink creates the lower edge and wall shadow. State always has a text equivalent: seat names, the inspector, the legend, and connection messages. A failed feed does not use red. It removes the live dot and working highlights, labels retained counts as last known, and prevents a new deal.

Measured rendered contrasts: muted on ink 5.29:1, jade on ink 6.23:1, ivory on ink 15.79:1, and ink on ivory 15.79:1. The wall's keyboard focus uses an ivory outline over a solid ink backing, so neighboring ivory tiles do not erase it. See `VALIDATION.md` for coverage and limitations.

## Typography

All fonts are bundled locally from pinned `@fontsource` packages, with regular weight 400 only. `font-synthesis: none` prevents invented weights. WOFF2 is preferred, with package-provided WOFF fallbacks. Font licenses ship in `dist/font-LICENSES.txt`; React, React DOM and Scheduler notices ship in `dist/runtime-LICENSES.txt`.

| Role | Family / fallback | Size and treatment |
| --- | --- | --- |
| Wordmark | Anton / Impact / sans-serif | `clamp(64px, 14vw, 200px)`, line height 1, tracking −0.035em |
| Compact wordmark | Anton | 28px, 24px below 600px |
| Section headings | Anton | `clamp(40px, 5vw, 64px)`, uppercase, line height 1.08, tracking −0.02em |
| Story headings | Anton | 28px desktop, 24px intermediate, 32px mobile |
| Body | Inter / sans-serif | 16px, line height 1.6–1.7; desktop tagline 17px |
| Numbers, labels, buttons, links | JetBrains Mono / monospace | Tabular numbers; labels generally 11–12px; 9–10px for compact chart/legend labels |
| Live counts | JetBrains Mono | 32px, 28px mobile |
| Seat input | JetBrains Mono | 16px at all widths |

Headings use balanced wrapping; descriptions use pretty wrapping. Article copy is constrained by its column and capped at 55ch on mobile. Body paragraphs remain selectable. Natural sentence case is stored in the source; CSS uppercases headings and button labels. Dense tile labels have complete accessible names and an equivalent larger inspector.

## Layout

Use `.container` for text and controls: maximum 1080px, 32px side gutters, reduced to 16px below 600px. The hero wall extends beyond that column with 8px edge insets. Major spacing follows an 8px grid: 16, 24, 32, 40, 48, 64, 96, and 144px. Small optical gaps and text spacing may use 2, 4, or 12px.

The desktop hero places the large wordmark beside the tagline/action. The wall is 80 columns by 25 rows at widths of at least 1000px. Between 600px and 999px it is 50 columns by 40 rows. Below 600px it is 40 columns by 50 rows; the introduction stacks. All 2,000 seats stay present, numbered 0–1999 as in the API. The 3:4 tile ratio determines wall height; it is roughly 575px at a 1440px viewport.

Below the wall, the live strip has four columns, becoming two on mobile. The story uses three columns, becoming a single column below 600px. Its 144px desktop top space becomes 96px on mobile. The trade flow remains a compact, three-stage row. Hand cards use 13 columns on desktop, seven below 1000px, and four below 600px. Hand actions wrap rather than overflow. No fixed overlay obscures content.

Rendered layouts were inspected at 1440px, 768px, and 320px, with additional breakpoint checks recorded in `VALIDATION.md`. The design supports English and a dark theme only.

## Elevation & Depth

The wall has one soft shadow, `0 24px 56px #0006`. Individual tiles have a light 1px top-left bevel and a darker 2px bottom-right edge; they have no persistent drop shadows. Keyboard focus adds a temporary solid 6px ink backing under its outline. The rest of the page uses background tones, open space, and 1px separators.

## Shapes

Tile faces, hand cards, and the small brand tile have 2px corner radii. Buttons and inputs have square corners. Buttons have a 1px ivory outline; the primary variant fills ivory with ink text. The live dot is circular. Decorative tile glyphs are local inline SVG circles and strokes, not external images or icon-font glyphs.

## Components

- `Mark` in `main.tsx`: large and compact wordmarks; the `AI` span is jade.
- `Glyph`: deterministic decorative SVG for each seat. It does not encode an agent's identity, skill, or performance.
- `.wall` / `.tile`: enrolled ivory, working red, open deep jade. Hover supplies the full native tooltip; activation opens the inspector. There is one tab stop within the wall. Arrow keys move a seat/row, Home/End select the extremes, Escape closes the inspector, and Tab exits normally. The inspector's 44px controls and numeric input provide the equivalent touch target for every tiny tile.
- `.button`: square 48px minimum-height action, primary and outline variants; hover, focus, disabled, and saving states. Dealing is unavailable while connecting or offline, with a nearby explanation.
- `.live-strip`: aggregate API counts and source age. Missing data uses an em dash; retained counts are explicitly marked after failure.
- `.heartbeat`: 24 real hourly buckets on a labeled logarithmic scale. The SVG accessible name includes every value. Missing hourly data has a text state, never a synthetic graph.
- `.hand-section`: frozen 13-seat snapshot, total and UTC timestamp; each tile links to its agent. `downloadCard` draws a 1600×1000 PNG using loaded local fonts. `postURL` opens an encoded draft, not an automatic post.
- `.story-grid`: three sections containing the assignment's exact copy and relevant explorer links.
- `.trade-flow`: labeled three-stage concept with moving jade markers. Its visible note explains the pinned ETH-pair discrepancy.

Motion lives inside `prefers-reduced-motion: no-preference`. The tile entrance is a 220ms ease-out flip, staggered by row in 20ms steps, finishing within 1.2 seconds at the largest row count. Hover tilts use the same duration/easing; working faces pulse every 1.6 seconds. Trade markers loop in 2.4 seconds. The Pause motion control stops wall and trade animations; reduced motion removes them entirely. The live dot and heartbeat do not animate.

## Do's and Don'ts

- Start another section with `.container`, the existing type hierarchy, and 8px spacing steps. Use one prominent primary action per section.
- Use jade for links/accents and reserve red for working tiles and the live dot. Keep secondary text at the actual muted token rather than reducing opacity.
- Preserve the exact wordmark clamp, 3:4 tile ratio, 2px gaps/radii, and square buttons.
- Keep API data labeled accurately. Do not fill network failures with sample counts, invent agent online status, or replace missing hourly activity with random bars.
- Keep wallet actions, eligibility claims, and trade execution out of this informational interface unless separately implemented and verified.
- Keep new assets local and URLs relative. Rebuild `dist/` after source changes.

Design review used Jakub Krehel's Better Interface (MIT, commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`). Documentation structure is adapted from Paul Bakaus's Impeccable (Apache-2.0, copyright 2025 Paul Bakaus, commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`). The text here documents this implementation; combined notices and licenses are retained in `web/design-guidance-LICENSE.txt`.
