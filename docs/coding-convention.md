# Mac Tool Kit Development Guidelines & Coding Convention

This document defines the architectural principles, Swift coding standards, UI/UX guidelines, and development workflows for the `mac-tool-kit` project. All future contributions and feature extensions must strictly adhere to these conventions.

---

## 1. Architectural Principles

### 1.1 Modularity & Extensibility
- **Mac Tool Kit Scope**: This repository serves as a native macOS utility toolkit suite. Future modules will add standalone and integrated utilities.
- **Core Abstraction (`MacToolKitCore`)**: Shared services, hardware monitors, low-level Mach/IOKit interfaces, data models, and common UI foundations must reside within `MacToolKitCore`.
- **Clean Architecture & MVVM**:
  - **Models**: Pure data representations adhering to `Identifiable`, `Codable`, and `Sendable`. Strictly no UI or business logic.
  - **Services / Engine**: Interface directly with macOS low-level Darwin subsystems (Mach Kernel, IOKit, libproc, sysctl). Expose asynchronous streams via modern Swift Concurrency.
  - **ViewModels**: Decorated with `@MainActor` and conforming to `ObservableObject` / `@Observable`. Manage state transitions, format transformations, and user actions.
  - **Views**: Declarative SwiftUI components designed for composability, previewability (Xcode Previews), and minimal overhead.

### 1.2 Modern Swift & Concurrency
- Full compliance with **Swift 6 Strict Concurrency**:
  - Avoid legacy blocking threads and deprecated `NSThread` / dispatch queues.
  - Heavy background operations (e.g. process enumeration, Docker CLI polling, SMC hardware queries) must run inside detached `Task` or dedicated actors to keep the Main Thread 100% responsive (60/120 FPS ProMotion).
  - All UI state updates must be isolated to `@MainActor`.
  - All shared data crossing task boundaries must conform to `Sendable`.

---

## 2. Code Style & Naming Conventions

### 2.1 Naming Standards
- **Types & Protocols**: `UpperCamelCase` (e.g. `SystemMetricsSnapshot`, `ProcessMonitorService`, `MetricCollectable`).
- **Variables & Functions**: `lowerCamelCase` (e.g. `cpuUsagePercentage`, `sampleProcesses()`).
- **Constants & Enum Cases**: `lowerCamelCase` (e.g. `case normal`, `case highSpike`).
- **File Names**: Must match the primary type declared within. Each file should encapsulate one cohesive responsibility.

### 2.2 Error Handling & Low-Level Safety
- When invoking C / Darwin / Mach APIs (`host_statistics64`, `proc_pidinfo`, `IOConnectCallStructMethod`):
  - Always enforce boundary checks, buffer length validations, and memory alignment safeguards.
  - Prevent illegal pointer dereferences and uninitialized memory access.
- For operations requiring elevated privileges (SMC fan override, `purge` cache):
  - Provide graceful degradation and transparent user prompts.
  - Never use force unwrapping (`!`) in production code paths.

---

## 3. UI/UX & Visual Guidelines

### 3.1 Native macOS Aesthetics
- Adhere to the latest macOS Human Interface Guidelines:
  - Translucent material / liquid glass cards with subtle borders.
  - High-contrast, clean sparkline graphs, tachometers, and gauges.
  - Seamless support for both Dark Mode and Light Mode.
- Multiple Presentation Surfaces:
  - **Menu Bar Extra (`MenuBarExtra`)**: Lightweight glanceable telemetry, fan status, and quick cleanup actions.
  - **Main Dashboard Window**: Comprehensive analytics, process trees, detailed graphs, and hardware controls.

### 3.2 Metrics & Units Standard
- Standardize all metric displays:
  - Percentage: `%` formatted to 1 decimal place (e.g. `14.2%`).
  - Memory & Storage: `MB`, `GB`, `TB` (binary units, $1\text{ GB} = 1024\text{ MB}$).
  - Network Throughput: `KB/s`, `MB/s`.
  - Fan Speed: `RPM`.
  - Thermal Telemetry: `°C`.

---

## 4. Contributing New Tools

To add a new tool or inspector to `mac-tool-kit`:
1. Extract shared services or telemetry into `MacToolKitCore`.
2. Create dedicated views and view models in `Sources/MacDashboardApp` or a new module under `Sources/`.
3. Follow the MVVM + Strict Concurrency architecture.
4. Add comprehensive unit tests in `Tests/MacToolKitCoreTests/`.
5. Update project documentation and screenshots.
