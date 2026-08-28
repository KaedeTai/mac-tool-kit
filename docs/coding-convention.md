# Mac Tool Kit 開發規範 (Coding Convention)

本文件定義 `mac-tool-kit` 專案的架構設計原則、Swift 程式碼風格、UI/UX 規範與開發流程。所有未來的開發與擴充皆必須嚴格遵守本規範。

---

## 1. 架構設計原則 (Architecture Principles)

### 1.1 模組化與可擴充性 (Modularity & Extensibility)
- 本專案定位為 **Mac 專屬小工具套件庫 (Mac Tool Kit)**，未來會持續新增各種獨立或整合式工具。
- 核心共用模組（如硬體監控、系統底層 API、共用 UI 元件、工具箱基礎設施）應收斂於 `MacToolKitCore` 或獨立 Core 模組。
- 每個獨立工具應用（如 `MacDashboardApp`）應保持高內聚、低耦合，遵循 **MVVM (Model-View-ViewModel)** 與 **Clean Architecture** 分層：
  - **Models**: 純資料結構，不可包含 UI 或業務邏輯，符合 `Identifiable`, `Codable`, `Sendable`。
  - **Services / Engine**: 負責與 macOS 底層 API（Mach Kernel, IOKit, libproc, sysctl）互動，提供非同步資料流（AsyncSequence / Combine / Swift Concurrency）。
  - **ViewModels**: 使用 `@Observable` 或 `@MainActor ObservableObject`，負責狀態管理、資料轉換與使用者操作響應。
  - **Views**: 純 SwiftUI 宣告式介面，維持輕量、可預覽（Xcode Previews）、高可讀性。

### 1.2 現代 Swift 與並行性規範 (Modern Swift & Concurrency)
- 全面採用 **Swift 6 / Modern Swift Concurrency**：
  - 避免傳統執行緒阻塞操作與過時的 `NSThread`。
  - 背景資料擷取（如每秒 polling 系統硬體狀態、遍歷數千個行程）必須在背景 `Task` 或專用 `actor` 中執行，嚴禁阻塞主執行緒（Main Thread）。
  - 所有 UI 狀態更新必須明確宣告於 `@MainActor`。
  - 資料模型在跨執行緒傳遞時必須符合 `Sendable` 協議。

---

## 2. 程式碼風格與命名規範 (Code Style & Naming Conventions)

### 2.1 命名規範 (Naming)
- **型別與協議 (Types & Protocols)**: 大駝峰命名法 (`UpperCamelCase`)，例如 `SystemMetricsSnapshot`, `ProcessMonitorService`, `MetricCollectable`。
- **變數與函式 (Variables & Functions)**: 小駝峰命名法 (`lowerCamelCase`)，例如 `cpuUsagePercentage`, `fetchActiveProcesses()`。
- **常數與列舉值 (Constants & Enum Cases)**: 小駝峰命名法 (`lowerCamelCase`)，例如 `case normal`, `case heavyLoad`。
- **檔案命名**: 與主要型別名稱完全一致，單一檔案原則上僅包含一個核心型別及其緊密相關的擴充。

### 2.2 錯誤處理與安全防護 (Error Handling & Safety)
- 呼叫系統底層 C / Mach API（如 `host_statistics64`, `proc_pidinfo`, `IOConnectCallStructMethod`）時，必須做完整的邊界檢查與錯誤防護，嚴禁非法的記憶體指標存取或未經初始化的記憶體解構。
- 針對需要特殊權限的操作（如修改 SMC 風扇設定、釋放系統快取記憶體），必須實作優雅降級（Graceful Degradation）機制，並提供明確的使用者引導與權限提示。
- 嚴禁使用 Force Unwrap (`!`)，除非在確定安全的靜態單元測試中。

---

## 3. UI / UX 與視覺規範 (UI & User Experience)

### 3.1 macOS 原生與精緻感 (Native & Modern Mac Feel)
- 介面設計應貼合最新 macOS 視覺語言：
  - 使用半透明背景（Material / Liquid Glass effect）。
  - 具備高對比、易於辨識的數據儀表板與即時圖表（Sparkline / Waveform / Gauge）。
  - 支援完整的深色模式（Dark Mode）與淺色模式（Light Mode）。
- 提供多種檢視型態：
  - **Menu Bar 常駐圖示 (MenuBarExtra)**: 提供常駐即時資訊摘要、快速切換風扇檔位與一鍵排障。
  - **完整監控主視窗 (Main Dashboard Window)**: 提供全方位指標細節、即時圖表、行程分析與歷史紀錄。

### 3.2 國際化與在地化 (Localization)
- 介面文案優先以 **繁體中文 (Traditional Chinese, zh-TW / zh-Hant)** 為主，並維持乾淨直觀的專有名詞標示。
- 數據單位統一規範：
  - 百分比：`%` (保留小數點一位，如 `14.2%`)
  - 記憶體/儲存空間：`MB` / `GB` / `TB` (採 1024 進位制)
  - 網路速率：`KB/s` / `MB/s`
  - 風扇轉速：`RPM` (轉/分)
  - 溫度：`°C`

---

## 4. 模組擴展指引 (Adding New Tools)

當要在本專案新增下一個小工具時，請遵循以下步驟：
1. 評估是否具備共用服務或 UI 元件，若有則沉澱至 `MacToolKitCore`。
2. 在 `Sources/` 下建立該工具的專屬模組或套件。
3. 遵循 MVVM 與非同步架構，編寫業務邏輯與介面。
4. 撰寫對應的單元測試，確保核心邏輯覆蓋率。
5. 更新專案文檔與說明。
