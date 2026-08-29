# MacDashboard master test matrix

This file maps release-impact paths to the executable and manual test cases maintained in `prd-tracker.json`.

## 1. System overview

**Component**: `Sources/MacDashboardApp/Views/OverviewView.swift`, `Sources/MacDashboardApp/ViewModels/DashboardViewModel.swift`

- `TC-OVERVIEW-001` — Reconcile CPU, RAM, disk, network, Docker, thermal and fan summary values with their named sources.

## 2. AI coding analytics and history

**Component**: `Sources/MacDashboardApp/Views/AIAnalyticsView.swift`, `Sources/MacDashboardApp/ViewModels/AIAnalyticsViewModel.swift`, `Sources/MacToolKitCore/AIAnalytics/`

- `TC-AI-001` — Verify project, main session, child session, model, token and API-equivalent estimate provenance.
- `TC-CODEX-SOURCE-001` — Read exact Codex task metadata and provider-reported usage.
- `TC-HIERARCHY-001` — Link children only through explicit parent identifiers.
- `TC-HISTORY-001` — Exercise Active, Recent 24h and permanent History lifecycle and bounded rendering.

## 3. Lag diagnosis

**Component**: `Sources/MacDashboardApp/Views/LagDetectiveView.swift`, `Sources/MacToolKitCore/Diagnostics/`

- `TC-LAG-001` — Verify verdict, causes and remediation agree without terminating the Dashboard itself.

## 4. CPU and memory

**Component**: `Sources/MacDashboardApp/Views/CPUView.swift`, `Sources/MacDashboardApp/Views/MemoryView.swift`, `Sources/MacToolKitCore/Metrics/CPUMonitor.swift`, `Sources/MacToolKitCore/Metrics/MemoryMonitor.swift`

- `TC-CPU-001` — Verify measured core load and disclosed topology derivation.
- `TC-MEMORY-001` — Verify RAM composition, derived pressure labels and automatic inactive-page reclaim explanation.

## 5. Disk, network and storage reclaim

**Component**: `Sources/MacDashboardApp/Views/DiskNetworkView.swift`, `Sources/MacToolKitCore/Metrics/DiskMonitor.swift`, `Sources/MacToolKitCore/Metrics/NetworkMonitor.swift`, `Sources/MacToolKitCore/Metrics/StorageAnalyzer.swift`

- `TC-DISK-NETWORK-001` — Verify disk units, live rates and 64-bit since-boot network counters.
- `TC-STORAGE-001` — Verify bounded named-path scan, exact cleanup allow-list, cancellation and Docker separation.

## 6. Thermal and fan control

**Component**: `Sources/MacDashboardApp/Views/ThermalFanView.swift`, `Sources/MacDashboardApp/ViewModels/FanControlViewModel.swift`, `Sources/MacToolKitCore/FanControl/`, `Sources/MacToolKitHardwareABI/`

- `TC-THERMAL-FAN-001` — Verify only named measured sensors are displayed and fan commands fail closed.

## 7. Process manager

**Component**: `Sources/MacDashboardApp/Views/ProcessTableView.swift`, `Sources/MacToolKitCore/Metrics/ProcessMonitor.swift`, `Sources/MacToolKitCore/Metrics/CommandLineRedactor.swift`

- `TC-PROCESS-001` — Verify measured process metrics, disclosed attribution and credential redaction.

## 8. Cross-page UI and package regression

**Component**: `Sources/MacDashboardApp/`, `Package.swift`, `scripts/`, `README.md`, `assets/screenshots/`

- `TC-RESPONSIVE-UI-001` — Inspect all eight tabs at the supported minimum window size.
- `TC-VISUAL-001` — Capture and read every installed-app tab after the final build.
- `TC-TEST-SUITE-001` — Run the coverage-enabled Swift test suite.
- `REL-README-001` — Render README references and verify every linked screenshot exists at Retina resolution.
- `REL-PACKAGE-001` — Build, sign, package, mount and launch-check the tagged DMG/ZIP artifacts.
