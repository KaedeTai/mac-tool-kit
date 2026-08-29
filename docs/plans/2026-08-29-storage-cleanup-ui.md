# Storage composition and safe cleanup plan

Date: 2026-08-29

## Understanding summary

- Add a measured storage composition to the Disk & Network tab.
- Let the operator select reclaim candidates by impact and run one confirmed cleanup.
- Explain externally managed storage such as Docker instead of mixing it into ordinary file deletion.
- Repair the Process Manager toolbar overflow and inspect all eight tabs at the installed-app viewport.
- Keep RAM purge removed: `purge(8)` clears disk buffer cache and cannot clear VM inactive pages.

## Assumptions

- The user previously approved following the recommended trustworthy-dashboard approach.
- Storage scans run only when the Disk tab requests them or the user refreshes them; they never join the one-second monitoring loop.
- Measured category bytes cover named user directories only. The remainder is labeled system, other users, APFS, or unscanned rather than assigned to a fabricated category.
- Cleanup starts with no selected items. Every selected item is shown again in a destructive confirmation.
- The cleanup sheet keeps cancellation in the fixed footer, away from the macOS title-bar drag region, and supports the standard Escape shortcut.

## Options considered

1. Direct one-click deletion: fastest, but it cannot surface impact and makes accidental data loss too easy.
2. Read-only storage explanation: safest, but it does not satisfy the requested reclaim workflow.
3. Measured inventory, impact selection, confirmation, and after-state measurement: selected because it keeps the action useful and auditable.

## Decision log

- Only exact allow-listed cleanup roots may be changed.
- Low impact: reproducible developer/package caches. Medium impact: logs that may be useful for debugging. High impact: Trash, because deletion is permanent.
- Docker is externally managed. Show Docker-reported reclaimable bytes and explain that ordinary prune excludes volumes; never include Docker volumes in the app cleanup selection.
- Downloads, project dependencies, application support, and other user-created content remain review-only.
- Report both the selected-item size decrease and the volume free-space delta after cleanup; neither is called a guaranteed result before execution.
- The Process Manager toolbar uses a width-aware two-row layout. Table columns remain horizontally scrollable at narrow widths instead of compressing labels vertically.

## Acceptance

- Storage category totals are measured from named paths and never exceed the reported used-volume total in the composition.
- Partial or permission-denied scans disclose that the result is incomplete.
- Cleanup rejects paths outside the injected exact allow-list.
- No cleanup occurs without a non-empty selection and a confirmation.
- The operator can cancel from the fixed footer or press Escape without invoking cleanup.
- Docker volumes and running containers are never deleted by this feature.
- The installed app is captured and inspected on every tab after the change.
