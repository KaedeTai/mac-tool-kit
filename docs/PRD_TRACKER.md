# PRD 驗收追蹤方式

`prd-tracker.json` 是 Mac Tool Kit 的本機驗收狀態單一來源；`docs/design-site/index.html` 是本次資料真實性稽核與下一版資訊架構的人工確認介面。

## 狀態定義

- `verified`：自動化測試與人工驗收都通過，而且證據來源可追溯。
- `implemented`：已實作，但完整驗收尚未完成。
- `partial`：已有部分功能或證據，仍存在失敗案例或缺口。
- `planned`：已定義需求，尚未實作。
- `blocked`：需要外部能力、帳號、資料或使用者決策。
- `not-covered`：需求存在，但沒有足夠測試或證據。

## 更新流程

1. PM 在 `prd_items` 補齊使用情境、驗收標準與決策。
2. QA 為每項情境建立可重跑的 test case，分開記錄 automated 與 manual 狀態。
3. Dev 開工與完成時更新 task、受影響檔案及測試證據。
4. 只有自動化與人工證據都通過時，才能標成 `verified`。

## 本輪基準

- 2026-08-29 已完成八個 tab 的 truth-safety 與最小視窗實作：資料來源分類、Active／Idle／Inactive、Recent 24h／永久 History、父子 Session、64-bit 網路、具名 IOHID 感測器、風扇讀回、行程秘密遮蔽、磁碟組成與分級清理。
- `swift test --enable-code-coverage`：104 tests passed、0 failures；整體 line coverage 95.61%（6,363 / 6,655 lines），已通過 repo 的 95% gate。
- 永久 AI history 寫入前會強制移除 raw turn 描述；此規則有獨立失敗／通過回歸測試。
- AI 介面只顯示「API 等價估算（非帳單）」；「實際扣款」已從 UI 拔除。估算預設顯示、帶 2026-08-28 官方費率版本，並按模型分桶計算 input／output／cache read／cache write。缺精確模型或 cache-write TTL 時不套 fallback。
- Release App 已更新至 `/Applications/MacDashboard.app`。八個 tab 都已逐頁擷取為 1440 × 1050 PNG 並以原始像素讀取；最終公開 AI 截圖只保留目前 mac-tool-kit 的真實 Active Codex session，關閉估算後清單與詳情均不再顯示估算。總覽的 Docker 狀態已改由 `docker ps` 合併，Lag 與 RAM 不再承諾固定釋放量。
- 已確認 helper 瞬間成功的根因：AppleSMC payload 只有 76 bytes（規格為 80），且第二次 SMC 回應不再攜帶 key metadata。1.1.0 helper 已在安裝環境讀回 2 個風扇的實際 RPM／範圍。元件溫度改走 Apple IOHID 具名來源：PMU tdie* 顯示為 SoC／PMU、NAND CH* 顯示為儲存裝置、電池使用 AppleSmartBattery；SMC Tp*／Tg*／Tm* 不再被猜成 CPU／GPU／RAM。
- 此機目前可讀 3 個來源群組、合計 16 個具名實測點：SoC／PMU 14、AppleSmartBattery 1、NAND CH0 1。群組卡保留最高值摘要；下方明細預設展開並逐點顯示系統原始名稱與即時溫度。18:07 安裝版已確認 PMU tdie1–14、AppleSmartBattery Temperature 與 NAND CH0 temp 全數出現，收合／展開也會正確移除與恢復明細；nil 類別與衍生最高值重複卡仍不顯示。
- AI Active 仍顯示所有真實 runtime 紀錄；Recent／History 預設把只有 session ID／路徑／時間戳的紀錄分到「僅活動紀錄」開關。本輪重現的 `review-the-current-uncommitted-generic-lovelace` 不再展開不存在的模型、token、費用欄位，也不納入用量彙總。
- Recent 專案列現在直接顯示主／子 Session 數量；目前選中的 Recent 子 Session 會揭露其唯一專案與父 Session 分支，但一般自動／手動刷新會保留使用者的收合狀態。`Unlinked Claude Runtime` 不再當作專案主 Session 呈現，而是標為 Claude 內部背景工作／獨立 Runtime；真正缺父紀錄的子 Session 則明示「找不到父 Session」。20:27 安裝版實測 ai-awesome 為 1 主＋166 子、artogo-infra 1 主＋136 子、ai-driven-company 1 主＋2 子、backend 0 主＋23 個缺父紀錄子 Session。
- History 實測索引為 6,244 筆／61 個專案／約 6.5 MB。History 預設只呈現收合專案列；專案、主 Session 與 Unlinked 群組可各自收合，每一分支每次最多載入 40 筆。最終安裝版也用一個有兩個明確子 Session 的真實主 Session 驗證：收合後子列與子分頁控制都消失。子 Session 關聯改成預建索引，History 不再背景重掃；Active／Recent 分別維持 10／30 秒更新。
- `purge(8)` 的本機手冊證明它只清 disk buffer cache，不影響 malloc／vm_allocate 的 anonymous memory，因此無法清除畫面上的 inactive pages。所有 purge 入口已移除，RAM 頁改為明示「非活躍頁面由 macOS 自動回收」。
- 磁碟頁新增「具名分類實測／磁碟已使用／未分類」組成。掃描只讀本機檔案系統配置區塊，不讀檔案內容，並設總時間上限；權限不足、雲端占位或逾時項目只顯示成功讀取部分的下限。21:16 安裝版在 10.76 秒觀察窗內完成，當下為 49.5 GiB 具名實測、525.9 GiB 已使用、476.3 GiB 未分類，8 個分類標為部分可讀；這些是當時的 live snapshot，不是永久數字。
- 「選擇並釋放空間」預設不勾任何項目，只允許固定白名單的可重建快取、日誌與垃圾桶；每項顯示路徑、影響和後果，並有第二次永久清除確認。真實使用者檔案未執行刪除；刪除與重新量測以 temporary fixture 驗證。Docker Images／Containers／Volumes／Build Cache 由 `docker system df` 分開回報；Dashboard 不提供可能刪資料庫的 volume prune。
- 行程管理員在 1000-point 最小寬度改為 compact columns：保留名稱／來源、CPU、RAM 與動作，類別、PID、已運作時間改到列明細。八個 tab 的最小視窗截圖已逐頁讀取，未再看到垂直文字、控制列重疊或主要操作被截斷。
- 風扇寫入與結束行程不為了測試而執行，維持 manual not-covered；purge 不再列為可驗證的 RAM 動作。
- GitHub Release [`v1.3.0`](https://github.com/PeterTing/mac-tool-kit/releases/tag/v1.3.0) 已公開且不是 draft／prerelease。DMG、ZIP 與 SHA256SUMS 共三個附件都已從公開網址重新下載；兩個發行包通過公布的 SHA-256。來源 tag 指向 `4778d2fe097fc5a1cc502a3476c303a9909ceef0`。
