# Session Handoff — MacDashboard v1.3.0 release

Updated: 2026-08-29 22:10 Asia/Taipei

## Current state

- `VERSION`, the app bundle, DMG and ZIP are aligned at `1.3.0`.
- README has been rewritten around explicit data provenance and now embeds all eight current Dashboard tabs.
- The eight public screenshots under `assets/screenshots/` are direct 1440 × 1050 PNG captures. Every file was opened at original detail and inspected for clipping, overlap and readability.
- The public AI screenshot is scoped to the current `mac-tool-kit` Active Codex session. The API-estimate toggle is off, and both the tree and selected-session evidence panel omit the estimate.
- A release-blocking UI inconsistency was found and fixed: the estimate toggle previously hid list values but not the selected-session detail. `AISessionCostPresentation` is now the shared gate and has a dedicated regression test.
- README and `docs/releases/v1.3.0.md` no longer claim eight temperature components, RAM purge, actual AI billing, or universal sensor availability.
- `scripts/build_app.sh` and `scripts/package_dmg.sh` read the version from `VERSION`; the packaged installation guide describes current evidence boundaries.

## Verification

- `swift test --enable-code-coverage`: 71 tests, 0 failures.
- Combined source line coverage: 71.04% (4,704 / 6,622 lines), below the repository 95% target.
- `INSTALL=1 ./scripts/build_app.sh`: release build succeeded and installed `/Applications/MacDashboard.app`.
- Installed app version: `1.3.0`; strict deep code-sign verification passed.
- DMG mounted read-only; embedded app version was `1.3.0` and strict code-sign verification passed.
- ZIP extracted; embedded app version was `1.3.0` and strict code-sign verification passed.
- DMG SHA-256: `edb15ff7579e99ec1706e335bd1ae128770a661333b5655f56622ad50dab8c95`.
- ZIP SHA-256: `eabd6afa9273ece25108b220d19430e9aa4546d6686c58328b20f7c6fca9948f`.
- README screenshot dimensions: eight of eight are 1440 × 1050 PNG.

## Source map

- Public product overview: `README.md`
- Release notes and limitations: `docs/releases/v1.3.0.md`
- Version source: `VERSION`
- App and archive packaging: `scripts/build_app.sh`, `scripts/package_dmg.sh`
- AI estimate display policy: `Sources/MacToolKitCore/AIAnalytics/AISessionTreePresentation.swift`
- AI tree and evidence panel: `Sources/MacDashboardApp/Views/AIAnalyticsView.swift`
- Estimate visibility regression: `Tests/MacToolKitCoreTests/TrustworthyDashboardTests.swift`
- Release artifacts: `dist/MacDashboard-v1.3.0-macOS.dmg`, `dist/MacDashboard-v1.3.0-macOS.zip`, `dist/SHA256SUMS.txt`
- Acceptance state: `prd-tracker.json`, `docs/PRD_TRACKER.md`, `docs/design-site/index.html`

## Exact next steps

1. Run repository hygiene, README-link, screenshot-dimension and package checksum checks.
2. Review the complete diff, then commit and push `main`.
3. Tag `v1.3.0`, create the GitHub Release with DMG, ZIP and `SHA256SUMS.txt`, and wait until the release is public.
4. Download all three public assets to a new temporary directory and verify the published checksums.
5. Update this handoff and `prd-tracker.json` with the final commit, tag, release URL and public-download evidence.

## Risks and deliberate gaps

- Coverage is 71.04%, below the 95% repository release policy; the final verdict must remain `unverified` even if the GitHub release is live.
- The app is ad-hoc signed and not Apple-notarized.
- No real user-file deletion, unrelated process termination, Docker volume deletion, or manual fan write was executed for release evidence.
- Automated pixel-diff regression is not configured; all eight final screenshots were manually inspected.
- Storage composition remains a bounded lower-bound scan, not Apple's private complete Storage index.
