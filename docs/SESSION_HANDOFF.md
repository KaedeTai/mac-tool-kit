# Session Handoff — MacDashboard v1.3.1 release candidate

Updated: 2026-08-30 23:25 Asia/Taipei

## Current state

- `VERSION`, the installed app, DMG, ZIP and Release Note are aligned at `1.3.1`.
- The release candidate includes the latest origin/main behavior-focused coverage and testability changes.
- GitHub tag, Release publication and unauthenticated public-download verification are still pending.
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

## Source map

- Public product overview: `README.md`
- Release notes and limitations: `docs/releases/v1.3.1.md`
- Version source: `VERSION`
- App and archive packaging: `scripts/build_app.sh`, `scripts/package_dmg.sh`
- Coverage expansion: `Tests/MacToolKitCoreTests/CoverageExpansionTests.swift`, `ParserAndStorageCoverageTests.swift`, `FanClientCoverageTests.swift`, `PrivilegedHelperManagerCoverageTests.swift`
- Testability seams: `Sources/MacToolKitCore/FanControl/FanHelperClient.swift`, `PrivilegedHelperManager.swift`, `Sources/MacToolKitCore/Metrics/ProcessMonitor.swift`
- Release artifacts: `dist/MacDashboard-v1.3.1-macOS.dmg`, `dist/MacDashboard-v1.3.1-macOS.zip`, `dist/SHA256SUMS.txt`
- Acceptance state: `prd-tracker.json`, `docs/PRD_TRACKER.md`, `docs/design-site/index.html`

## Remaining release steps

1. Commit and push the v1.3.1 release source.
2. Create and push tag `v1.3.1` at the exact release-source commit.
3. Publish the GitHub Release with DMG, ZIP and `SHA256SUMS.txt`.
4. Download all three public attachments again, compare checksums and re-open the published packages.

## Risks and deliberate gaps

- The app is ad-hoc signed and not Apple-notarized.
- No real user-file deletion, unrelated process termination, Docker volume deletion or manual fan write was executed for release evidence.
- Automated pixel-diff regression is not configured; this patch changes no UI source and retains the previously inspected screenshots.
- Storage composition remains a bounded lower-bound scan, not Apple's private complete Storage index.
