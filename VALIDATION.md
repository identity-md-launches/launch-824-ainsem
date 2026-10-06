# AINSEM website validation

Worker record, 2026-10-07 Asia/Taipei (browser/API timestamps 2026-10-06 UTC). These are local checks, not independent certification.

## Scope and assumptions

Implemented one static page in `web/`, exported to `dist/`. Retained the prior contract implementation and its build configuration/dependencies. The interface reads the public IMD swarm, displays 2,000 seats, deals 13 enrolled agents, downloads a PNG, and opens an X draft. It includes the requested story and trade-flow copy. Dark theme and English are the supported variants.

Read the pinned project, deployment, network, Better Interface workflow, core principles of all six domains, documentation method, and license. The existing project contained Solidity but no frontend. No wallet or transaction flow was requested. The provided contract provenance is retained in `web/deployment.json`; its ETH pool conflicts with the requested IMD trade narrative. A visible clarification explains this. No allocation size/proofs/schedule were supplied for $ANSEM holders; the site says that claim details are unavailable.

Official API discovery used [IMD's documentation](https://imd.fun/docs/), followed by actual open-CORS responses from `/swarm` and `/steps/hourly`. Only the required public data fields are consumed. Per-seat online status is absent, so a hand samples enrolled agents from a fresh live response and explicitly says so. `accepted` is a work-submission counter, not unique whole jobs; this is clarified next to the required X wording. Hourly activity uses a labeled logarithmic scale. No fabricated feed or chart data is shipped.

## Commands and actual results

All commands were run from the repository root unless specified. Dependencies were installed only under the existing ignored `test/scratch/` area; npm's cache was placed in `/tmp`. A first attempted install hit the read-only default cache and an unavailable Anton package version. Using `/tmp/ainsem-npm-cache` and registry-confirmed Fontsource 5.3.0 resolved both. The final lockfile install succeeded and reported zero vulnerabilities.

```sh
cp -R web/. test/scratch/frontend/
npm --cache /tmp/ainsem-npm-cache ci --prefix test/scratch/frontend
cp -R web/. test/scratch/frontend/
AINSEM_OUT_DIR="$PWD/dist" npm --prefix test/scratch/frontend run build
npm --prefix test/scratch/frontend run typecheck
npm --prefix test/scratch/frontend test
node web/scripts/check-export.mjs
git diff --check
```

| Check | Actual result |
| --- | --- |
| Clean lockfile installation | Exit 0; 30 packages installed, 0 reported vulnerabilities |
| Production build | Exit 0; Vite 8.3.3, 20 modules transformed; final JS `index-BWQJgSu4.js`, CSS `index-BYqNedWb.css` |
| Typecheck | Exit 0; `tsc --noEmit` |
| Node/tsx tests | Exit 0; 6 tests passed, 0 failed |
| Static export integrity | Exit 0; all 9 relative HTML/CSS asset references resolve; export files total **378,933 bytes** |
| Whitespace check | Exit 0; `git diff --check` |

Tests in `web/tests/data.test.ts` cover seat zero and aggregate counters, stale/future/unreachable/malformed feeds, distinct 13-seat sampling, immutable snapshot totals and timestamps, insufficient enrollment, exact encoded X copy, and valid/invalid 24-hour heartbeat payloads. These use deterministic fixtures only in tests; production requests real data.

The production export was served under `http://localhost:4173/dist/` by a bounded foreground `timeout 1200 python3 -m http.server 4173 --bind 0.0.0.0` command. The browser tool was available; a managed `test/scratch/browser/preview.json` was not provided. The local preview therefore used this temporary server. The browser was closed and the server stopped after inspection.

## Browser interaction evidence

The browser tool inspected Chromium screenshots, page state, keyboard actions, computed styles, downloads, network requests, and console messages on the production export, not Vite development output.

| Flow/state | Observation |
| --- | --- |
| Real live data | Both API endpoints returned 200; counts and working tiles populated. All three intended font faces reported `loaded`. Local JS, CSS, font and favicon requests returned 200. No console errors or warnings were recorded. |
| Deal | On the final build, 13 cards had 13 distinct explorer URLs. Their accepted counts summed to **19,992**, matching the displayed total and decoded X draft. Focus moved to `#hand-title`. |
| Share | Draft text was exactly `My AINSEM hand: 13 live IMD agents, 19992 accepted jobs between them. Dealt from the swarm at 2026-10-06 18:27:02 UTC.` The intent's encoded `text` parameter matched. No post was published or account used. |
| Download | Browser reported successful PNG downloads, including `AINSEM-hand-2026-10-06T18-27-02-753Z.png`. A 1600×1000 card was inspected; local fonts, all 13 seat IDs, counts, total and UTC time rendered. An example is `artifacts/hand-card.png`. |
| Keyboard | Tab reached skip link, navigation, Deal, then the wall as a single tab stop. ArrowRight selected #1. End selected #1999, and Tab exited to Pause motion. Full seat information appeared in the inspector. Focus was visible; the final edge focus was re-inspected after the backing/inset fix. |
| Empty seat | Both the native title and inspector read exactly `Seat #1999, not enrolled yet`. |
| Numeric inspector | Entering `1999.9` normalized to `1999`; the selected tile, inspector and tooltip matched. The numeric field measured 88×44px and previous/next controls each 44×44px. |
| Offline and recovery | Replaced only the page's fetch function with a rejecting function for one polling cycle. The exact offline message and Retry appeared; counts were marked last known, the live state cleared, and dealing did not replace the existing hand. Restoring fetch and activating Retry recovered the live state. No production fallback fixture was added. |
| Reduced motion | Emulating `prefers-reduced-motion: reduce` left zero active animations. |
| Pause motion | Under no-preference, clicking Pause set `aria-pressed=true`; every remaining animation's state was `paused`. |
| Navigation | Native page/hash links and explorer/token/agent destinations were checked. The trade-flow label has a valid group role. No route rewrite is required. |

Final overflow checks at widths **320, 390, 599, 600, 768, 999, 1000 and 1440px** all returned `scrollWidth === innerWidth`. Each retained exactly 2,000 tiles. Respective wall columns were 40 below 600, 50 below 1000, and 80 above. Screenshots were visually inspected at 320×800, 768×1000, and 1440×900/1000. Both sides of the breakpoints were checked geometrically. The final mobile story/trade/footer, hand layout, and edge focus were also inspected.

Saved final evidence:

- `artifacts/desktop.webp`: 1440×900 hero.
- `artifacts/mobile.webp`: 320×800 hero after the stacking fix.
- `artifacts/hand.webp`: final dealt hand, total, and actions.
- `artifacts/keyboard.webp`: final mobile edge focus and equivalent seat controls.
- `artifacts/trade-mobile.webp`: narrow trade flow, provenance note, footer.
- `artifacts/hand-card.png`: actual downloaded card.
- `artifacts/browser-network.txt`: final resource/API request record.

Artifacts are separate worker evidence and are not runtime dependencies. The repository's pre-existing local exclude rule already excludes `artifacts/`; it was not modified. This durable root report and a copy at `artifacts/validation.md` contain the review record. Generated browser snapshots were moved to ignored `test/scratch/browser-session/`.

## Six-domain Better Interface review

| Domain | Coverage | Findings, fixes and limits |
| --- | --- | --- |
| Accessibility | **Checked**: semantic landmarks/headings, native actions, accessible labels, keyboard path, focus, reduced motion, equivalent seat controls, live regions, axe scan | Fixed the unlabeled-role mismatch on the diagram and wall-edge focus treatment. No screen-reader session or physical-device test. See axe manual-review items below. |
| Layout | **Checked**: full-width wall, content alignment, grouping, mobile stacking, breakpoint reflow and hand/action wrapping | Corrected cramped 320px hero copy and eliminated a partial intermediate wall row. Native 200% browser zoom was not tested. RTL/localization are not supported variants. |
| Writing | **Checked**: required copy, action labels, offline/retry messages, seat tooltip, X template and explanatory limits | Preserved required wording and surfaced the verified ETH-pair and unprovided allocation details. Clarified enrolled-vs-online seats and work-submission counts. No price forecasts or return promises added. |
| Typography | **Checked**: actual loaded fonts, regular weights, wordmark clamp, uppercase display type, tabular numbers, wrapped body/labels | Rechecked mobile hero wrapping after fix. Dense tile/legend labels are intentionally small and have larger text equivalents. Cross-browser font rasterization was not tested. |
| Colors | **Checked**: exact requested palette, red usage, actual opaque text/background pairs, focus backing | Computed ratios from browser styles: muted/ink **5.29:1**, jade/ink **6.23:1**, ivory/ink **15.79:1**, ink/ivory **15.79:1**. Decorative glyph and animation-opacity pairs were not certified as meaningful text. Light theme is not applicable. |
| UI | **Checked**: tile proportions/edges, button shape, hover/focus, loading/offline/empty states, saved hand, animations, pause | Fixed focus backing and error proximity; inspected downloaded PNG. Motion duration/easing checked in CSS; reduced/pause states checked in browser. A 10%-speed animation-panel replay was not performed. |

### Consolidated findings and corrections

Line references identify the final source locations that contain the fixes.

| Severity | Source | Evidence / impact | Correction and recheck |
| --- | --- | --- | --- |
| Medium | `web/src/style.css:848` | The first 320px screenshot placed tagline and CTA in adjacent columns, forcing a four-line tagline. | Stack the mobile copy/action; final screenshot shows the two intended tagline lines and an inset button. No horizontal overflow. |
| Medium | `web/src/main.tsx:599` | Axe's manual-review output flagged `aria-label` on a generic trade-flow div. | Added `role="group"`; final scan no longer reports `aria-prohibited-attr`. |
| Medium | `web/src/style.css:332`, `web/src/style.css:872` | Initial final-seat focus extended into the narrow viewport edge; jade over neighboring ivory was an unreliable ring background. | Added solid ink backing with ivory outline and preserved 8px wall insets. Final keyboard screenshot shows the entire indicator inside the viewport. |
| Medium | `web/src/main.tsx:235` | A failed deal could report only below the full wall, far from the initiating hero action. | Added a nearby connection explanation and `aria-disabled`/`aria-describedby` state. Handler still blocks disconnected deals; retry restores them. |
| Low | `web/src/main.tsx:99` | A 64-column intermediate grid left the final row mostly empty. | Use 50 columns in that range; final width checks confirm 40 complete rows. |
| Low | `web/src/main.tsx:142` | Numeric seat selection could accept fractional/non-finite IDs that had no tile. | Normalize to a finite, truncated, bounded ID; browser injection of 1999.9 produced selected seat 1999 and the correct tooltip. |

Final axe scan (WCAG 2 A/AA, 2.1 AA, 2.2 AA tags): **0 violations, 23 rule passes**. It left **7 color-contrast manual-review nodes** (decorative non-text glyphs/ambiguous background detection) and **2,000 target-size manual-review nodes** for the deliberately dense wall. The inspector provides equivalent access through measured 44px controls, and arrow-key navigation avoids 2,000 tab stops. The scan does not establish full accessibility compliance; no screen-reader session, forced-colors rendered review, native 200% zoom, physical touch-device session, Safari or Firefox test was performed.

## Integrity and size

No existing protected build/dependency path was changed; no ignore file was changed. New frontend manifests and the lockfile are under `web/`. Dependencies and browser scratch files are not submission candidates. No vendored npm registry/archive or Git submodule was added. The production export contains no node_modules, cache, server, credentials, or source maps.

The measured baseline Git bundle is **99,433 bytes**. Before this report, the 73 submission-candidate files totaled **1,403,947 raw bytes**; adding that entire raw tree, the baseline bundle and 1,024 bytes overhead per file gave **1,578,132 bytes**, below the 8,388,608-byte limit with substantial headroom. The final audit follows below. This conservatively budgets the original history plus all current file contents rather than relying on a compression estimate.

Final byte/path audit: **76 candidate files, 1,424,804 raw bytes; conservative history + tree + overhead budget 1,602,061 bytes**, below **8,388,608 bytes**. No generated dependencies, browser scratch files, protected-path changes, or submodules are included.

The final rebuild added runtime license notices; browser-reviewed JS and CSS hashes remained unchanged.

## Completion and remaining limitations

**Complete for the stated website scope.** Production build, typecheck, useful interaction checks, rendered review, local fixes, source/lockfile/export delivery, design documentation, and install/preview/publish instructions are present. The feed remains an external availability dependency; freshness depends on reasonable client/server clocks. Individual online status, holder eligibility and an IMD trading route are not verified or invented. The site was not published to a host, no X post was sent, and no chain transaction was made. Historical contract tests were preserved but not rerun for this frontend task.

Review guidance: Jakub Krehel, Better Interface, MIT, commit `267330e1adfc66a718fb65fa6918c1f06d0a689e`; documentation method: Paul Bakaus, Impeccable, Apache-2.0, commit `9d715cc4f5564a990ca8345abfdd5df6dc9b41c8`. Notices and licenses are retained in `web/design-guidance-LICENSE.txt`.
