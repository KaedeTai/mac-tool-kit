# Session Handoff — MacDashboard v1.3.1 public release

Updated: 2026-08-30 23:30 Asia/Taipei

## Current state

- `VERSION`, the installed app, DMG, ZIP and Release Note are aligned at `1.3.1`.
- GitHub Release [`v1.3.1`](https://github.com/PeterTing/mac-tool-kit/releases/tag/v1.3.1) is public, non-draft and non-prerelease.
- Tag `v1.3.1` resolves to release-source commit `2314663f63159d2fc422368157842dd90a9f480b`, which includes the latest behavior-focused coverage and testability changes.
- Coverage exercises AI value models and pricing, provider parsers, summary/history/runtime/tree behavior, storage boundaries, live read-only metrics, hardware presentation, lag diagnosis, the fan socket protocol and privileged-helper outcomes.
- The visible UI is unchanged from v1.3.0, so the eight existing direct 1440 × 1050 PNG screenshots remain the applicable visual evidence.

## Fresh verification

- `swift test --enable-code-coverage`: 104 tests, 0 failures.
- Combined source line coverage: 95.63% (6,364 / 6,655 lines), above the repository 95% target.
- Coverage command: `xcrun llvm-cov report .build/arm64-apple-macosx/debug/mac-tool-kitPackageTests.xctest/Contents/MacOS/mac-tool-kitPackageTests -instr-profile=.build/arm64-apple-macosx/debug/codecov/default.profdata -ignore-filename-regex='Tests/|\.build/'`.
- `./scripts/package_dmg.sh`: release build and versioned packaging succeeded without compiler warnings.
- Installed app version: `1.3.1`; strict deep code-sign verification passed.
- DMG mounted read-only; embedded app version was `1.3.1` and strict code-sign verification passed.
- ZIP extracted; embedded app version was `1.3.1` and strict code-sign verification passed.
- DMG SHA-256: `9b9b47321ff422d8a1c0cff347a2f926df7a471bed732dcf8388a0b2c6473b78`.
- ZIP SHA-256: `6a5099890cb730b6366616e0aacfcd287a92d9e1a553dca2c59f900fae187dc0`.
- README screenshot dimensions: eight of eight are 1440 × 1050 PNG.
- GitHub reports DMG, ZIP and `SHA256SUMS.txt` as uploaded assets; the release page returns HTTP 200.
- All three assets were downloaded again from public URLs. The public checksum manifest passed for both packages; the public DMG and ZIP reported version `1.3.1` and passed strict deep code-sign verification.
- No GitHub Actions workflows are configured for this repository, so `gh run list --branch main` returned no runs; local Tier 3 evidence is the build/test gate.

## Source map

- Public product overview: `README.md`
- Release notes and limitations: `docs/releases/v1.3.1.md`
- Version source: `VERSION`
- App and archive packaging: `scripts/build_app.sh`, `scripts/package_dmg.sh`
- Coverage expansion: `Tests/MacToolKitCoreTests/CoverageExpansionTests.swift`, `ParserAndStorageCoverageTests.swift`, `FanClientCoverageTests.swift`, `PrivilegedHelperManagerCoverageTests.swift`
- Testability seams: `Sources/MacToolKitCore/FanControl/FanHelperClient.swift`, `PrivilegedHelperManager.swift`, `Sources/MacToolKitCore/Metrics/ProcessMonitor.swift`
- Release artifacts: `dist/MacDashboard-v1.3.1-macOS.dmg`, `dist/MacDashboard-v1.3.1-macOS.zip`, `dist/SHA256SUMS.txt`
- Acceptance state: `prd-tracker.json`, `docs/PRD_TRACKER.md`, `docs/design-site/index.html`

## Rollout ledger

- Source: release-source commit and tag verified at `2314663f63159d2fc422368157842dd90a9f480b`.
- CI/build: GitHub Actions not configured; fresh local tests, coverage, release build and signing passed.
- Candidate: local DMG/ZIP mount or extraction, version, signature and checksums passed.
- Cutover: GitHub Release is public, non-draft and non-prerelease with three uploaded assets.
- Public route: release page HTTP 200; public DMG/ZIP/checksum downloads passed.
- Changed behavior: coverage and testability paths passed 104 native tests; no UI source changed.
- Data/runtime: no schema migration or persistent-data cutover in this patch.
- Monitoring: terminal `LIVE`; GitHub asset states are `uploaded` and public re-download verification passed.

## Risks and deliberate gaps

- The app is ad-hoc signed and not Apple-notarized.
- No real user-file deletion, unrelated process termination, Docker volume deletion or manual fan write was executed for release evidence.
- Automated pixel-diff regression is not configured; this patch changes no UI source and retains the previously inspected screenshots.
- Storage composition remains a bounded lower-bound scan, not Apple's private complete Storage index.
