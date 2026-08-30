import Foundation
import Darwin

public final class LagDetective: Sendable {
    public init() {}

    public func diagnose(
        cpu: CPUUsageSnapshot,
        memory: MemoryUsageSnapshot,
        processes: [ProcessItem],
        batteryThermal: BatteryThermalSnapshot,
        diskIO: DiskIOSnapshot
    ) -> LagDiagnosticReport {
        var score = 100
        var causes: [LagCauseItem] = []
        var actions: [RemediationAction] = []
        let actionableProcesses = processes.filter { process in
            process.bundleIdentifier != "com.peterting.mac-tool-kit.dashboard"
                && process.rawName != "MacDashboardApp"
        }

        // 1. CPU Analysis
        if cpu.totalUsage > 85.0 {
            score -= 25
            causes.append(LagCauseItem(
                category: "CPU 瓶頸",
                title: "CPU 總負載過高 (\(String(format: "%.1f", cpu.totalUsage))%)",
                detail: "處理器處於極高負載狀態，可能導致系統介面卡頓或輸入延遲。",
                iconName: "cpu",
                isMajor: true
            ))
        } else if cpu.totalUsage > 60.0 {
            score -= 10
            causes.append(LagCauseItem(
                category: "CPU 負載",
                title: "CPU 負載偏高 (\(String(format: "%.1f", cpu.totalUsage))%)",
                detail: "有多個任務正在頻繁調用處理器資源。",
                iconName: "cpu",
                isMajor: false
            ))
        }

        // Check Top CPU Process
        if let topCPU = actionableProcesses.first(where: { $0.cpuPercentage > 50.0 }) {
            score -= 15
            let projStr = topCPU.projectName != nil ? "在 [\(topCPU.projectName!)] 專案中" : ""
            let triggerStr = topCPU.triggerAppName != nil ? "由 \(topCPU.triggerAppName!) 執行的 " : ""

            if let ai = topCPU.aiContext {
                let aiHeader = "\(ai.toolName)" + (ai.modelName != nil ? " (\(ai.modelName!))" : "")
                let aiSession = ai.sessionShortId != nil ? " • 推導 Context \(ai.sessionShortId!)" : ""
                let taskPart = ai.taskSummary != nil ? " [\(ai.taskSummary!)]" : ""

                causes.append(LagCauseItem(
                    category: "AI 運算尖峰",
                    title: "🤖 \(aiHeader)\(aiSession) 行程負載尖峰 (\(String(format: "%.1f", topCPU.cpuPercentage))% CPU)",
                    detail: "PID \(topCPU.pid)（\(triggerStr)\(projStr)\(taskPart)已運作 \(topCPU.formattedUptime)）：\(topCPU.terminationImpact)。",
                    iconName: "brain.head.profile",
                    isMajor: true
                ))

                actions.append(RemediationAction(
                    typeId: "kill_cpu_hog",
                    title: "中止 \(ai.toolName) 相關行程",
                    explanation: "中止推導為 \(ai.toolName)（模型: \(ai.modelName ?? "不可取得")）的 PID \(topCPU.pid)。CPU 百分比是當次取樣，不承諾釋放固定比例。",
                    buttonTitle: "結束 AI 行程 (PID \(topCPU.pid))",
                    iconName: "stop.circle.fill",
                    pid: topCPU.pid,
                    isDestructive: true
                ))
            } else {
                causes.append(LagCauseItem(
                    category: "行程高負載",
                    title: "「\(topCPU.name)」佔用過多 CPU (\(String(format: "%.1f", topCPU.cpuPercentage))%)",
                    detail: "PID \(topCPU.pid)（\(triggerStr)\(projStr)已運作 \(topCPU.formattedUptime)）：\(topCPU.terminationImpact)。",
                    iconName: "flame.fill",
                    isMajor: true
                ))

                actions.append(RemediationAction(
                    typeId: "kill_cpu_hog",
                    title: "結束 \(topCPU.name)",
                    explanation: "\(topCPU.terminationImpact)（\(triggerStr)\(projStr)已運作 \(topCPU.formattedUptime)）。目前 CPU 樣本為 \(String(format: "%.1f", topCPU.cpuPercentage))%；終止後的實際差異需重新取樣確認。",
                    buttonTitle: "結束「\(topCPU.name.prefix(16))」(PID \(topCPU.pid))",
                    iconName: "xmark.circle.fill",
                    pid: topCPU.pid,
                    isDestructive: true
                ))
            }

            actions.append(RemediationAction(
                typeId: "renice_cpu_hog",
                title: "降低 \(topCPU.name) 優先權",
                explanation: "將該行程優先級調至最低，讓出核心資源給前景視窗與操作介面。",
                buttonTitle: "降速運行 (Renice)",
                iconName: "arrow.down.circle.fill",
                pid: topCPU.pid,
                isDestructive: false
            ))
        }

        // 2. Memory & Swap Analysis
        if memory.pressureState == .critical || memory.usedPercentage > 92.0 {
            score -= 30
            causes.append(LagCauseItem(
                category: "記憶體告急",
                title: "RAM 記憶體壓力過高 (\(String(format: "%.1f", memory.usedPercentage))%)",
                detail: "Dashboard 的 active + wired + compressed 衍生比例或 swap 門檻已達警戒；這不是 Activity Monitor 的官方 Memory Pressure。",
                iconName: "memorychip",
                isMajor: true
            ))

            actions.append(RemediationAction(
                typeId: "open_memory_inspector",
                title: "檢查實際高用量行程",
                explanation: "macOS 會自動回收 inactive pages；系統 purge 只清 disk buffer cache，不能把非活躍 RAM 手動清零。請從行程實測值找出可關閉的工作負載。",
                buttonTitle: "查看記憶體排行",
                iconName: "list.bullet.rectangle",
                isDestructive: false
            ))
        } else if memory.pressureState == .warning || memory.usedPercentage > 80.0 {
            score -= 10
            causes.append(LagCauseItem(
                category: "記憶體偏高",
                title: "實體記憶體使用率達 \(String(format: "%.1f", memory.usedPercentage))%",
                detail: "背景程式開啟較多，可適時清理不常用應用程式。",
                iconName: "memorychip",
                isMajor: false
            ))
        }

        // Swap Thrashing Check
        if memory.swapUsedBytes > 3 * 1024 * 1024 * 1024 {
            score -= 20
            let swapGB = Double(memory.swapUsedBytes) / (1024 * 1024 * 1024)
            causes.append(LagCauseItem(
                category: "Swap 使用量",
                title: "Swap 交換空間使用過大 (\(String(format: "%.1f", swapGB)) GiB)",
                detail: "目前已配置的 swap 容量偏高；單次容量快照不能證明正在頻繁換頁或就是卡頓原因。",
                iconName: "externaldrive.badge.exclamationmark",
                isMajor: true
            ))
        }

        // Top Memory Hogs
        let hasSystemMemoryConcern = memory.pressureState == .warning
            || memory.pressureState == .critical
            || memory.usedPercentage > 80.0
        let memHogs = hasSystemMemoryConcern
            ? actionableProcesses.filter { $0.memoryBytes > 2 * 1024 * 1024 * 1024 }
            : []
        for hog in memHogs.prefix(2) {
            let hogGB = Double(hog.memoryBytes) / (1024 * 1024 * 1024)
            causes.append(LagCauseItem(
                category: "高 RAM 應用",
                title: "「\(hog.name)」佔用 \(String(format: "%.1f", hogGB)) GiB 記憶體",
                detail: "PID \(hog.pid) 佔用大量記憶體空間。",
                iconName: "shippingbox.fill",
                isMajor: false
            ))
            // Avoid duplicate action if already added for CPU
            if !actions.contains(where: { $0.pid == hog.pid }) {
                actions.append(RemediationAction(
                    typeId: "kill_mem_hog",
                    title: "結束 \(hog.name)",
                    explanation: "目前取樣顯示該行程佔用 \(String(format: "%.1f", hogGB)) GiB；終止後的實際可用量不保證，需重新取樣確認。",
                    buttonTitle: "結束應用（目前佔用 \(String(format: "%.1f", hogGB)) GiB）",
                    iconName: "xmark.circle",
                    pid: hog.pid,
                    isDestructive: true
                ))
            }
        }

        // 3. Thermal Throttling Analysis
        if batteryThermal.thermalState == .serious || batteryThermal.thermalState == .critical {
            score -= 25
            causes.append(LagCauseItem(
                category: "系統熱狀態",
                title: "macOS 回報 Serious / Critical 熱狀態",
                detail: "ProcessInfo thermalState 顯示熱壓可能影響效能；Dashboard 沒有晶片溫度或頻率讀值，不能斷言特定元件正在降頻。",
                iconName: "thermometer.high",
                isMajor: true
            ))

            // Thermal state alone does not prove that a writable fan controller
            // or a safe control-grade temperature sensor is available. Report
            // the cause without promising a remediation action we cannot verify.
        }

        // 4. Disk I/O Bottleneck
        let totalDiskSpeedMB = (diskIO.readBytesPerSec + diskIO.writeBytesPerSec) / (1024 * 1024)
        if totalDiskSpeedMB > 350.0 {
            score -= 10
            causes.append(LagCauseItem(
                category: "磁碟密集 I/O",
                title: "SSD 讀寫速率達 \(String(format: "%.0f", totalDiskSpeedMB)) MiB/s",
                detail: "硬碟正在進行巨量資料傳輸，可能暫時佔用 I/O 頻寬。",
                iconName: "arrow.up.arrow.down.square.fill",
                isMajor: false
            ))
        }

        // Clamp final score
        let finalScore = min(100, max(0, score))

        // Determine Severity
        let severity: LagSeverity
        let summary: String

        let hasMajorCause = causes.contains(where: \.isMajor)
        if hasMajorCause && finalScore >= 40 {
            severity = .moderate
            summary = "偵測到至少一個主要瓶頸；分數尚可不代表沒有卡頓來源，請查看原因與可驗證的處置建議。"
        } else if finalScore >= 85 {
            severity = .smooth
            summary = "目前規則沒有從 CPU、衍生 RAM 比例、swap、熱狀態與磁碟速率快照中找到明顯瓶頸；這不等於已排除所有卡頓原因。"
        } else if finalScore >= 65 {
            severity = .minor
            summary = "規則偵測到輕度資源負載；是否造成體感卡頓仍需對照發生時間。"
        } else {
            severity = .severe
            summary = "規則偵測到多個高風險資源訊號；請先核對原因與行程身分，再決定是否執行修復。"
        }

        return LagDiagnosticReport(
            healthScore: finalScore,
            severity: severity,
            summary: summary,
            causes: causes,
            suggestedActions: actions,
            timestamp: Date()
        )
    }
}
