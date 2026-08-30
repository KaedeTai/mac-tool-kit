# Session Handoff — MacDashboard coverage gate

Updated: 2026-08-30 12:22 Asia/Taipei

## Current state

- GitHub Release [`v1.3.0`](https://github.com/PeterTing/mac-tool-kit/releases/tag/v1.3.0) is public, non-draft and non-prerelease. Tag `v1.3.0` resolves to source commit `4778d2fe097fc5a1cc502a3476c303a9909ceef0`.
- The current working tree has raised combined source line coverage from 71.04% to 95.61% with behavior-focused tests. These local changes are not yet committed, tagged, or rebuilt into the published v1.3.0 artifacts.
- Coverage now exercises AI value models and pricing, provider parsers, summary/history/runtime/tree behavior, storage boundaries, live read-only metrics, hardware presentation, lag diagnosis, the fan socket protocol, and privileged-helper success/failure outcomes.
- `FanHelperClient` and `PrivilegedHelperManager` gained internal dependency-injection seams so socket and administrator-script behavior can be tested without changing the public shared-client defaults or performing privileged writes.
- The unreachable Lag severity branch was removed after tests covered every reachable score/cause combination; the user-visible severe verdict remains covered by combined critical signals.
- `VERSION`, the app bundle, DMG, ZIP, tag and Release Note are aligned at `1.3.0`.
- README has been rewritten around explicit data provenance and now embeds all eight current Dashboard tabs.
- The eight public screenshots under `assets/screenshots/` are direct 1440 × 1050 PNG captures. Every file was opened at original detail and inspected for clipping, overlap and readability.
- The public AI screenshot is scoped to the current `mac-tool-kit` Active Codex session. The API-estimate toggle is off, and both the tree and selected-session evidence panel omit the estimate.
- A release-blocking UI inconsistency was found and fixed: the estimate toggle previously hid list values but not the selected-session detail. `AISessionCostPresentation` is now the shared gate and has a dedicated regression test.
- README and `docs/releases/v1.3.0.md` no longer claim eight temperature components, RAM purge, actual AI billing, or universal sensor availability.
- `scripts/build_app.sh` and `scripts/package_dmg.sh` read the version from `VERSION`; the packaged installation guide describes current evidence boundaries.

## Verification

- `swift test --enable-code-coverage`: 104 tests, 0 failures.
- Combined source line coverage: 95.61% (6,363 / 6,655 lines), above the repository 95% target.
- Coverage command: `xcrun llvm-cov report .build/arm64-apple-macosx/debug/mac-tool-kitPackageTests.xctest/Contents/MacOS/mac-tool-kitPackageTests -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata -ignore-filename-regex='Tests/|\.build/'`.
- `INSTALL=1 ./scripts/build_app.sh`: release build succeeded and installed `/Applications/MacDashboard.app`.
- Installed app version: `1.3.0`; strict deep code-sign verification passed.
- DMG mounted read-only; embedded app version was `1.3.0` and strict code-sign verification passed.
- ZIP extracted; embedded app version was `1.3.0` and strict code-sign verification passed.
- DMG SHA-256: `edb15ff7579e99ec1706e335bd1ae128770a661333b5655f56622ad50dab8c95`.
- ZIP SHA-256: `eabd6afa9273ece25108b220d19430e9aa4546d6686c58328b20f7c6fca9948f`.
- README screenshot dimensions: eight of eight are 1440 × 1050 PNG.
- GitHub reports all three assets as uploaded. The DMG, ZIP and `SHA256SUMS.txt` were downloaded again from their public release URLs; both archive checksums passed.
- Local `main`, `origin/main` and the release tag all resolved to `4778d2fe097fc5a1cc502a3476c303a9909ceef0` at the release cutover. This handoff update is the only post-release documentation follow-up.

## Source map

- Public product overview: `README.md`
- Release notes and limitations: `docs/releases/v1.3.0.md`
- Version source: `VERSION`
- App and archive packaging: `scripts/build_app.sh`, `scripts/package_dmg.sh`
- AI estimate display policy: `Sources/MacToolKitCore/AIAnalytics/AISessionTreePresentation.swift`
- Coverage expansion: `Tests/MacToolKitCoreTests/CoverageExpansionTests.swift`, `ParserAndStorageCoverageTests.swift`, `FanClientCoverageTests.swift`, `PrivilegedHelperManagerCoverageTests.swift`
- Testability seams: `Sources/MacToolKitCore/FanControl/FanHelperClient.swift`, `PrivilegedHelperManager.swift`
- AI tree and evidence panel: `Sources/MacDashboardApp/Views/AIAnalyticsView.swift`
- Estimate visibility regression: `Tests/MacToolKitCoreTests/TrustworthyDashboardTests.swift`
- Release artifacts: `dist/MacDashboard-v1.3.0-macOS.dmg`, `dist/MacDashboard-v1.3.0-macOS.zip`, `dist/SHA256SUMS.txt`
- Acceptance state: `prd-tracker.json`, `docs/PRD_TRACKER.md`, `docs/design-site/index.html`

## Follow-up priorities

1. Review and commit the current coverage/testability changes before cutting a future release; do not imply that v1.3.0 contains them.
2. Add an automated screenshot/layout baseline for all eight tabs.
3. If fully automated installation is required, sign with a Developer ID certificate and notarize the DMG/ZIP workflow.
4. Keep destructive acceptance isolated: use a user-approved disposable cache fixture, never unrelated live data or Docker volumes.

## Risks and deliberate gaps

- Coverage is 95.61%; future source growth still needs accompanying tests so CI does not regress below 95%.
- The coverage result applies to the current working tree, not the published v1.3.0 commit or downloadable artifacts.
- The app is ad-hoc signed and not Apple-notarized.
- No real user-file deletion, unrelated process termination, Docker volume deletion, or manual fan write was executed for release evidence.
- Automated pixel-diff regression is not configured; all eight final screenshots were manually inspected.
- Storage composition remains a bounded lower-bound scan, not Apple's private complete Storage index.
