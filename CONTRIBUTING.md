# 貢獻指南 (Contributing Guide)

感謝您對 **MacDashboard (mac-tool-kit)** 的關注與支持！我們非常歡迎社群共同參與開發、回報問題或提出改進建議。

為了確保代碼品質、系統穩定性與良好的協作體驗，請在提交貢獻前閱讀以下指引：

---

## 🛠️ 開發環境需求

- **macOS**：macOS 14.0 (Sonoma) 或更高版本（建議在 Apple Silicon Mac 上測試完整溫控功能）
- **Xcode / Swift**：Swift 6.0+ 工具鏈
- **套件管理**：Swift Package Manager (SPM)

---

## 🚀 貢獻工作流程 (Workflow)

1. **Fork 儲存庫**：點擊專案右上角的 `Fork` 按鈕，將儲存庫複製至您的個人帳號。
2. **建立功能分支**：
   ```bash
   git checkout -b feature/your-feature-name
   # 或修復 Bug：
   git checkout -b fix/your-bug-fix
   ```
3. **進行開發與測試**：
   - 確保所有修改皆符合嚴格並行性（Swift 6 Strict Concurrency）。
   - 請參閱 [`docs/coding-convention.md`](docs/coding-convention.md) 遵守架構與命名規範。
4. **執行本地測試與驗證**：
   ```bash
   # 確保所有單元測試 100% 通過
   make test

   # 測試編譯發布版本
   make release
   ```
5. **提交 Commit**：
   請採用 [Conventional Commits](https://www.conventionalcommits.org/) 格式規範，例如：
   - `feat: add GPU frequency monitor`
   - `fix: prevent potential nil unwrapping in SMC bridge`
   - `docs: update troubleshooting guide for fan helper`
6. **建立 Pull Request (PR)**：
   - 推送至您的分支：`git push origin feature/your-feature-name`
   - 至本儲存庫提出 PR，並詳細填寫改動摘要、測試方式與關聯的 Issue。

---

## 📋 開發規範要點 (Key Principles)

1. **嚴格遵守 `docs/coding-convention.md`**：所有代碼架構、分層（`MacToolKitCore` vs `MacDashboardApp`）、異步模型均需依照規範實作。
2. **Swift 6 並行安全**：使用 `@MainActor`、`Sendable` 與現代 `async/await`，禁止引入 Data Race 隱患。
3. **零外部肥大依賴**：核心監控功能優先採用 macOS 原生 Darwin / IOKit 系統 API，維持極致輕量與純粹。
4. **保留單元測試**：若新增了新的 Metrics Monitor 或演算法，請於 `Tests/MacToolKitCoreTests/` 同步補充對應的 XCTest 測試案例。

---

## 🐛 回報問題與建議 (Reporting Issues)

- 若您發現了 Bug，請至 [Issues 頁面](https://github.com/PeterTing/mac-tool-kit/issues) 並使用 **`Bug Report`** 模板提交。
- 若您有新的功能需求或想法，請使用 **`Feature Request`** 模板建立討論。

再次感謝您對開源生態的貢獻！❤️
