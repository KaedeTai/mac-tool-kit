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
        if let topCPU = processes.first(where: { $0.cpuPercentage > 50.0 }) {
            score -= 15
            let projStr = topCPU.projectName != nil ? "在 [\(topCPU.projectName!)] 專案中" : ""
            let triggerStr = topCPU.triggerAppName != nil ? "由 \(topCPU.triggerAppName!) 執行的 " : ""

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
                explanation: "\(topCPU.terminationImpact)（\(triggerStr)\(projStr)已運作 \(topCPU.formattedUptime)）。可立即釋放 \(String(format: "%.1f", topCPU.cpuPercentage))% 核心運算。",
                buttonTitle: "結束「\(topCPU.name.prefix(16))」(PID \(topCPU.pid))",
                iconName: "xmark.circle.fill",
                pid: topCPU.pid,
                isDestructive: true
            ))

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
                detail: "實體記憶體即將耗盡，系統正在頻繁進行記憶體壓縮與分頁交換。",
                iconName: "memorychip",
                isMajor: true
            ))

            actions.append(RemediationAction(
                typeId: "purge_memory",
                title: "釋放系統快取記憶體",
                explanation: "清除磁碟快取與不活躍分頁，快速騰出可用實體記憶體空間。",
                buttonTitle: "一鍵釋放 RAM",
                iconName: "sparkles",
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
                category: "虛擬交換顛簸",
                title: "Swap 交換空間使用過大 (\(String(format: "%.1f", swapGB)) GB)",
                detail: "系統頻繁將記憶體寫入 SSD 硬碟，會造成顯著的點擊卡死與彩球轉圈現象。",
                iconName: "externaldrive.badge.exclamationmark",
                isMajor: true
            ))
        }

        // Top Memory Hogs
        let memHogs = processes.filter { $0.memoryBytes > 2 * 1024 * 1024 * 1024 }
        for hog in memHogs.prefix(2) {
            let hogGB = Double(hog.memoryBytes) / (1024 * 1024 * 1024)
            causes.append(LagCauseItem(
                category: "高 RAM 應用",
                title: "「\(hog.name)」佔用 \(String(format: "%.1f", hogGB)) GB 記憶體",
                detail: "PID \(hog.pid) 佔用大量記憶體空間。",
                iconName: "shippingbox.fill",
                isMajor: false
            ))
            // Avoid duplicate action if already added for CPU
            if !actions.contains(where: { $0.pid == hog.pid }) {
                actions.append(RemediationAction(
                    typeId: "kill_mem_hog",
                    title: "結束 \(hog.name)",
                    explanation: "釋放 \(String(format: "%.1f", hogGB)) GB 記憶體空間。",
                    buttonTitle: "結束應用 (釋放 \(String(format: "%.1f", hogGB)) GB)",
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
                category: "溫度過熱降頻",
                title: "晶片溫度過高，系統正在主動降頻",
                detail: "硬體過熱保護觸發，CPU/GPU 運算頻率被強迫調低以保護元件。",
                iconName: "thermometer.high",
                isMajor: true
            ))

            actions.append(RemediationAction(
                typeId: "fan_max_cooling",
                title: "啟動強效散熱冷卻",
                explanation: "將風扇轉速提升至全速，加速排出熱量並解除溫度降頻。",
                buttonTitle: "啟動全速散熱",
                iconName: "snowflake",
                isDestructive: false
            ))
        }

        // 4. Disk I/O Bottleneck
        let totalDiskSpeedMB = (diskIO.readBytesPerSec + diskIO.writeBytesPerSec) / (1024 * 1024)
        if totalDiskSpeedMB > 350.0 {
            score -= 10
            causes.append(LagCauseItem(
                category: "磁碟密集 I/O",
                title: "SSD 讀寫速率達 \(String(format: "%.0f", totalDiskSpeedMB)) MB/s",
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

        if finalScore >= 85 {
            severity = .smooth
            summary = "目前系統效能處於極佳狀態，資源分配合理，無延遲卡頓跡象。"
        } else if finalScore >= 65 {
            severity = .minor
            summary = "系統負載稍微增加，但仍能順暢處理各項工作。"
        } else if finalScore >= 40 {
            severity = .moderate
            summary = "系統出現中度資源吃緊或溫度升高，建議查看上方分析原因並清理高佔用程式。"
        } else {
            severity = .severe
            summary = "⚠️ 偵測到嚴重卡頓瓶頸！多個關鍵資源（CPU / RAM / 溫度）處於超載狀態，請立即執行修復動作。"
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
