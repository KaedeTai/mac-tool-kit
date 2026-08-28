# Mac Tool Kit 🛠️ (MacDashboard)

> 🚀 **專為 macOS 打造的高性能全能系統監控、智慧卡頓偵探與 Apple Silicon 閉迴路溫控工具箱。**  
> 純原生 Swift 6 與 SwiftUI 構建，具備低資源消耗、毫秒級診斷與頂級毛玻璃質感介面。

---

## 🌟 核心特色 (Key Features)

### 1. 全機 8 大核心硬體元件即時溫度儀表盤 (Component Temperatures)
- 💻 **Apple Silicon SoC 晶片 (SoC Package)**：監控整合晶圓封裝整體熱能。
- 🖥️ **CPU 運算核心群**：即時 P-Cores / E-Cores 核心熱度。
- 🎮 **GPU 圖形渲染核心**：3D 渲染與 Metal 著色核心溫度。
- 🧠 **ANE 神經網路引擎 (AI NPU)**：CoreML / 本機 AI 模型推理單元溫度。
- ⚡ **統一記憶體 (Unified RAM)**：SoC 兩側 LPDDR5 晶粒溫度。
- 🖐️ **掌托與電池 (Palm Rest & Battery)**：結合實體電池感測器與鋁合金機身導熱模型，精準反映打字手感溫度。
- 🌪️ **散熱鰭片與出風口 (Heatsink)**：排風導管與鰭片溫度。
- 💾 **SSD 固態硬碟 (NVMe Storage)**：隨即時 I/O 吞吐量動態反映快閃記憶體顆粒溫度。

### 2. 智慧閉迴路自訂基準溫控 (Sensor-Based Closed-Loop Fan Control)
- **自由切換基準元件**：點擊任一元件卡片，風扇即可專門為該元件（如專門降溫掌托、專門壓制 SoC）進行動態調速。
- **工業級溫控遲滯防抖演算法 (Thermal Hysteresis & Anti-Hunting)**：
  - **-7°C 寬廣遲滯死區**：升速門檻 $\ge \text{Target} + 0.8^\circ\text{C}$，降速門檻 $< \text{Target} - 7.0^\circ\text{C}$，徹底告別臨界點頻繁開關噪音。
  - **強效極限壓溫 (Max Turbo)**：起步 3,800 RPM，超溫時輸出 5,100+ RPM 渦輪大風量快速壓溫。
  - **EMA 指數平滑濾波**與**轉速變化斜率限制**。
- **特權硬體控制 (XPC Mach SMC Root Controller)**：
  - 雙通道架構：相容 Macs Fan Control XPC SMC 協議與內建 Helper。
  - 支援手動固定轉速滑桿 (1,200 ~ 6,200 RPM)。
  - 一鍵安裝 / 一鍵卸載還原原廠自動。

### 3. 智慧 Lag 瓶頸診斷器 (Lag Detective) ⚡
- **卡頓原因秒級分析**：智慧辨識 CPU 暴衝、RAM 枯竭、Swap 顛簸、溫度降頻與 SSD 密集讀寫。
- **一鍵智慧修復 (One-Click Remedies)**：一鍵釋放系統快取記憶體 (Purge RAM)、一鍵關閉卡死程式、一鍵啟動全速散熱。

### 4. 深度系統效能監控
- **CPU 處理器**：全核心即時負載網格與歷史波動曲線。
- **RAM 記憶體**：活躍、聯動、壓縮與記憶體壓力等級。
- **磁碟儲存與 I/O**：APFS 掛載卷容量、SSD 即時讀寫速率 (MB/s)。
- **網路上下行**：即時上傳/下載吞吐量與即時 Sparkline 趨勢圖。
- **程序檢查器 (Process Inspector)**：支援關鍵字搜尋、使用者 App 過濾、一鍵 Force Quit 與 Renice。
- **選單列常駐 (Menu Bar App)**：隨時於頂部選單列快速檢視各項核心指標。

---

## 📦 下載與安裝 (Installation)

### 方式一：下載發布打包檔
前往專案發布頁面或從本地編譯產生的 `dist/` 目錄取得：
- **💿 `MacDashboard-v1.0.0-macOS.dmg`**：雙擊開啟後將 `MacDashboard` 拖入 `Applications` 即可。
- **🤐 `MacDashboard-v1.0.0-macOS.zip`**：解壓縮後直接執行。

### 方式二：從原始碼編譯
```bash
# 複製專案
git clone https://github.com/PeterTing/mac-tool-kit.git
cd mac-tool-kit

# 執行測試
make test

# 編譯並安裝至 /Applications
make release

# 或打包生成 DMG 安裝映像檔
make dmg
```

---

## 🛠️ 開發與架構 (Architecture)

- **語言與框架**：Swift 6 (Strict Concurrency), SwiftUI, Combine
- **系統底層串接**：IOKit (`AppleSmartBattery`, `AppleSMC`), Darwin Mach Kernel APIs, `sysctl`, `host_statistics64`
- **架構設計**：
  - `MacToolKitCore`：核心硬體監控、診斷與 SMC 通訊庫。
  - `MacDashboardApp`：原生 SwiftUI 雙模態使用者介面（獨立視窗 + 選單列）。
  - `MacDashboardFanHelper`：輕量級 SMC 特權守護進程。

---

## 📄 開發規範 (Coding Convention)

所有開發皆嚴格遵循 [`docs/coding-convention.md`](docs/coding-convention.md) 之規範。

---

## 📜 開源授權 (License)

本專案採用 [MIT License](LICENSE) 授權。歡迎自由 Fork、提交 PR 或提出 Issue 與建議！
