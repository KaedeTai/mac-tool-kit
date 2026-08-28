<div align="center">

# 🛠️ MacDashboard (Mac Tool Kit)

**專為 macOS 打造的高性能全能系統監控、智慧卡頓偵探與 Apple Silicon 閉迴路溫控工具箱**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/PeterTing/mac-tool-kit?color=purple)](https://github.com/PeterTing/mac-tool-kit/releases/latest)

<p align="center">
  純原生 <b>Swift 6</b> 與 <b>SwiftUI</b> 構建，具備極低資源消耗、全機 8 大元件獨立溫控、毫秒級卡頓排查與精緻毛玻璃質感。
</p>

[📥 下載最新安裝檔 (DMG / ZIP)](https://github.com/PeterTing/mac-tool-kit/releases/latest) •
[📖 使用方法指南](#-使用方法指南-usage-guide) •
[💡 核心特色](#-核心特色-key-features) •
[🤝 貢獻指南](#-貢獻指南-contributing) •
[🐛 問題回報](#-問題回報與-issue-提交-reporting-issues)

---

</div>

## 📸 實機功能截圖 (Screenshots)

### 1. 即時全景系統效能儀表板 (Overview Dashboard)
> 一目了然全系統 CPU 總量與歷史曲線、RAM 記憶體壓力分佈、磁碟容量與 I/O 速率、網路即時上下行 Sparkline 波動圖與電池健康度。

<div align="center">
  <img src="assets/screenshots/overview_dashboard.png" alt="Overview Dashboard" width="900" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);">
</div>

<br>

### 2. 全機 8 大元件即時溫度儀表盤與閉迴路風扇控制 (Thermal & Fan Control)
> 支援自由指定「溫控基準元件」（如專為掌托吹風降溫、為 Apple Silicon SoC 晶片壓溫），並搭載 **-7°C 遲滯防抖演算法**，徹底杜絕臨界點頻繁開關噪音。

<div align="center">
  <img src="assets/screenshots/thermal_fan_control.png" alt="Thermal Fan Control" width="900" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);">
</div>

<br>

### 3. 實體記憶體架構與一鍵快取釋放 (Memory RAM Inspector)
> 深入可視化活躍 (Active)、聯動 (Wired)、壓縮 (Compressed) 與可用記憶體，監控 Swap 交換區狀態，並支援 **一鍵釋放系統快取 (Purge RAM)**。

<div align="center">
  <img src="assets/screenshots/memory_inspector.png" alt="Memory Inspector" width="900" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);">
</div>

<br>

### 4. 行程資源監控與檢查器 (Process Inspector)
> 支援使用者 App / 系統背景進程一鍵過濾、關鍵字即時搜尋、按 CPU / RAM 佔用即時排序，並提供一鍵強制結束 (Force Quit) 功能。

<div align="center">
  <img src="assets/screenshots/process_inspector.png" alt="Process Inspector" width="900" style="border-radius: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.2);">
</div>

---

## 🌟 核心特色 (Key Features)

- 🔥 **全機 8 大核心硬體即時溫度網格**：
  - 💻 **Apple Silicon SoC 晶片 (SoC Package)**：整合晶圓封裝整體熱能。
  - 🖥️ **CPU 運算核心群**：即時 P-Cores 效能核 / E-Cores 節能核溫度。
  - 🎮 **GPU 圖形渲染核心**：3D 渲染與 Metal 著色核心溫度。
  - 🧠 **ANE 神經網路引擎 (AI NPU)**：CoreML / 本機 AI 模型運算溫度。
  - ⚡ **統一記憶體 (Unified RAM)**：SoC 兩側 LPDDR5 晶粒溫度。
  - 🖐️ **掌托與電池 (Palm Rest & Battery)**：結合實體電池感測器與鋁合金機身導熱模型，精準呈現打字手感溫度。
  - 🌪️ **散熱鰭片與出風口 (Heatsink)**：螢幕轉軸下方散熱鰭片與風道溫度。
  - 💾 **SSD 固態硬碟 (NVMe Storage)**：隨即時 I/O 讀寫吞吐量（MB/s）動態跳動。
- ❄️ **自訂基準元件閉迴路調速 (Sensor-Based Fan Control)**：
  - 點選任一元件卡片，即可將其設為專屬散熱基準（例如：專門冷卻掌托防止打字手燙、專門冷卻 SoC 晶片）。
  - **-7°C 寬廣遲滯防抖演算法**：升速門檻 $\ge \text{Target} + 0.8^\circ\text{C}$，降速門檻 $< \text{Target} - 7.0^\circ\text{C}$，杜絕頻繁開關噪音。
  - **強效極限壓溫 (Max Turbo)**：起步 3,800 RPM，超溫時輸出 5,100+ RPM 渦輪大風量快速壓溫。
  - **特權硬體控制 (XPC Mach SMC Root Controller)**：相容 Macs Fan Control XPC SMC 協議與內建 Helper，支援手動滑桿與一鍵完整卸載還原原廠。
- ⚡ **智慧 Lag 瓶頸診斷器 (Lag Detective)**：
  - 毫秒級自動歸因卡頓根因，並提供一鍵釋放記憶體 (Purge RAM)、一鍵全速降溫等救急功能。
- 🎛️ **雙模態視覺體驗**：
  - **Menu Bar 常駐選單列**：頂部選單列隨時查看溫度、風扇轉速、CPU 與記憶體。
  - **獨立全景視窗**：支援 Liquid Glass 毛玻璃質感與暗黑模式。

---

## 📖 使用方法指南 (Usage Guide)

### 1. 下載與安裝
1. 前往 [Releases 頁面](https://github.com/PeterTing/mac-tool-kit/releases/latest) 下載最新版 **`MacDashboard-v1.0.0-macOS.dmg`**。
2. 雙擊開啟 DMG 映像檔，將 **`MacDashboard`** 圖示拖曳至右側的 **`Applications`** 資料夾。
3. 進入「應用程式」啟動 `MacDashboard` 即可！

### 2. 啟用硬體風扇控制 (SMC Root Privilege)
1. 進入左側導航欄的 **「風扇與散熱 (Thermal & Fan)」** 頁面。
2. 點擊頂部的 **「啟用硬體風扇控制 (需授權)」** 按鈕。
3. 輸入您的 macOS 管理員密碼以授權特權助手（此步驟相容於 Macs Fan Control 的 XPC SMC 協議）。
4. 授權完成後，即可自由切換散熱策略或手動拉動轉速滑桿（1,200 ~ 6,200 RPM）。
5. 若想還原原廠，隨時點擊 **「解除特權助手」** 即可一鍵完整卸載並還原 Apple 原廠微碼控制。

### 3. 設定專屬「溫控基準元件」
1. 在「全機各硬體元件即時溫度」區域中，**點擊任一元件卡片**（例如：點擊 `🖐️ 掌托與電池`）。
2. 在下方散熱策略中選擇 **「智慧溫控 (目標 ≤ 34°C)」**。
3. 當掌托溫度超過 34°C 時，風扇會自動加速排熱，主動將掌托吹涼至舒適範圍！

---

## 🛠️ 本地編譯與開發 (Building from Source)

```bash
# 1. 複製專案庫
git clone https://github.com/PeterTing/mac-tool-kit.git
cd mac-tool-kit

# 2. 執行單元測試 (確保 10/10 測試全數通過)
make test

# 3. 編譯並安裝至 /Applications
make release

# 4. 打包生成 DMG 安裝映像檔與 ZIP 壓縮包
make dmg
# 生成檔案位於 dist/ 目錄中
```

---

## 🤝 貢獻指南 (Contributing)

我們非常歡迎社群參與貢獻！無論是提交 Bug 修復、新增感測器支援、或是優化 UI，都十分感謝您的投入。

詳細的開發規範、分支命名、Conventional Commits 與 Swift 6 並行安全指引，請閱讀 [**CONTRIBUTING.md**](CONTRIBUTING.md)。

---

## 🐛 問題回報與 Issue 提交 (Reporting Issues)

若您在使用過程中發現任何異常或有新功能想法，請透過 GitHub Issues 與我們聯繫：

- 🐞 **錯誤回報 (Bug Report)**：[點此提交 Bug](https://github.com/PeterTing/mac-tool-kit/issues/new?template=bug_report.md)
- 💡 **功能建議 (Feature Request)**：[點此提出新想法](https://github.com/PeterTing/mac-tool-kit/issues/new?template=feature_request.md)

---

## 📜 開源授權 (License)

本專案採用 [MIT License](LICENSE) 授權開源。歡迎自由使用、修改與分享！
