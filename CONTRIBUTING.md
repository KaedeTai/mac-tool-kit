# Contributing to MacDashboard (Mac Tool Kit)

Thank you for your interest in contributing to **MacDashboard (mac-tool-kit)**! We warmly welcome contributions from the community, whether reporting bugs, requesting new features, or submitting code improvements.

To maintain high code quality, system stability, and a smooth collaboration experience, please review the following guidelines before submitting your contribution.

---

## 🛠️ Development Requirements

- **Operating System**: macOS 14.0 (Sonoma) or newer (Apple Silicon recommended for complete thermal and SMC fan control testing).
- **Toolchain**: Swift 6.0+ toolchain / Xcode 16+.
- **Package Manager**: Swift Package Manager (SPM).

---

## 🚀 Contribution Workflow

1. **Fork the Repository**: Click `Fork` in the top-right corner to copy the repo to your GitHub account.
2. **Create a Feature Branch**:
   ```bash
   git checkout -b feature/your-feature-name
   # or for bug fixes:
   git checkout -b fix/your-bug-fix
   ```
3. **Develop and Test**:
   - Ensure all changes comply with **Swift 6 Strict Concurrency**.
   - Review and adhere to [`docs/coding-convention.md`](docs/coding-convention.md) for architectural and naming standards.
4. **Run Local Verification**:
   ```bash
   # Run the entire test suite (must pass 100%)
   make test

   # Verify Release build compilation
   make release
   ```
5. **Format Commit Messages**:
   Follow [Conventional Commits](https://www.conventionalcommits.org/) standards, for example:
   - `feat: add GPU frequency monitor`
   - `fix: prevent potential nil unwrapping in SMC bridge`
   - `docs: update troubleshooting guide for fan helper`
6. **Submit a Pull Request (PR)**:
   - Push your branch: `git push origin feature/your-feature-name`
   - Open a PR against `main` with a clear summary of changes, test instructions, and related issues.

---

## 📋 Key Architectural Principles

1. **Adhere to `docs/coding-convention.md`**: Maintain clean layer separation (`MacToolKitCore` vs `MacDashboardApp`).
2. **Swift 6 Concurrency Safety**: Use `@MainActor`, `Sendable`, and structured `async/await` without introducing data races.
3. **Zero Heavy External Dependencies**: Prioritize native macOS Darwin / IOKit system APIs to maintain ultra-low CPU/RAM footprint.
4. **Comprehensive Unit Testing**: When adding new metrics monitors or algorithms, include matching unit tests under `Tests/MacToolKitCoreTests/`.

---

## 🐛 Reporting Issues & Feedback

- Found a bug? Open an issue using the **[Bug Report](https://github.com/PeterTing/mac-tool-kit/issues/new?template=bug_report.md)** template.
- Have a feature idea? Share it using the **[Feature Request](https://github.com/PeterTing/mac-tool-kit/issues/new?template=feature_request.md)** template.

Thank you for helping make MacDashboard better for everyone! ❤️
