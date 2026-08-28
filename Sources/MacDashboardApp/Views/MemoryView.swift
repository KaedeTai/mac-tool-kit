import SwiftUI
import MacToolKitCore

public struct MemoryView: View {
    @ObservedObject var dashboardVM: DashboardViewModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Top Memory Stats Card
                GlassCard(title: "實體記憶體總覽 (RAM Architecture)", iconName: "memorychip.fill", accentColor: .purple) {
                    VStack(spacing: 16) {
                        HStack(spacing: 24) {
                            CircularGaugeView(
                                percentage: dashboardVM.memorySnapshot.usedPercentage,
                                title: "已使用記憶體",
                                subtitle: "\(String(format: "%.1f", Double(dashboardVM.memorySnapshot.usedBytes) / (1024*1024*1024))) / \(String(format: "%.0f", Double(dashboardVM.memorySnapshot.totalPhysicalBytes) / (1024*1024*1024))) GB",
                                iconName: "memorychip",
                                size: 110
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("已使用記憶體比例:").foregroundColor(.secondary)
                                    Spacer(minLength: 16)
                                    Text(String(format: "%.1f%%", dashboardVM.memorySnapshot.usedPercentage))
                                        .font(.system(size: 13, weight: .bold))
                                }

                                HStack {
                                    Text("記憶體壓力狀態:").foregroundColor(.secondary)
                                    Spacer(minLength: 16)
                                    StatBadge(
                                        text: dashboardVM.memorySnapshot.pressureState.rawValue,
                                        iconName: dashboardVM.memorySnapshot.pressureState == .normal ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                                        color: dashboardVM.memorySnapshot.pressureState == .normal ? .green : .red
                                    )
                                }

                                HStack {
                                    Text("交換空間 (Swap):").foregroundColor(.secondary)
                                    Spacer(minLength: 16)
                                    Text("\(String(format: "%.2f", Double(dashboardVM.memorySnapshot.swapUsedBytes) / (1024*1024*1024))) GB / \(String(format: "%.2f", Double(dashboardVM.memorySnapshot.swapTotalBytes) / (1024*1024*1024))) GB")
                                        .font(.system(size: 12, weight: .semibold))
                                }

                                Button {
                                    dashboardVM.purgeMemory()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "sparkles")
                                        Text("一鍵釋放系統快取 (Purge RAM)")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.purple)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                                .help("清除系統磁碟緩衝區與釋放使用者空間快取記憶體")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.system(size: 13))
                        }

                        Divider()

                        // Memory Stack Visualizer
                        VStack(alignment: .leading, spacing: 6) {
                            Text("記憶體組成結構分佈:")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            GeometryReader { geo in
                                let total = max(1.0, Double(dashboardVM.memorySnapshot.totalPhysicalBytes))
                                let activeW = geo.size.width * CGFloat(Double(dashboardVM.memorySnapshot.activeBytes) / total)
                                let wiredW = geo.size.width * CGFloat(Double(dashboardVM.memorySnapshot.wiredBytes) / total)
                                let compW = geo.size.width * CGFloat(Double(dashboardVM.memorySnapshot.compressedBytes) / total)
                                let inactW = geo.size.width * CGFloat(Double(dashboardVM.memorySnapshot.inactiveBytes) / total)
                                let freeW = geo.size.width * CGFloat(Double(dashboardVM.memorySnapshot.freeBytes) / total)

                                HStack(spacing: 2) {
                                    Rectangle().fill(Color.blue).frame(width: max(0, activeW))
                                    Rectangle().fill(Color.red).frame(width: max(0, wiredW))
                                    Rectangle().fill(Color.purple).frame(width: max(0, compW))
                                    Rectangle().fill(Color.orange).frame(width: max(0, inactW))
                                    Rectangle().fill(Color.green.opacity(0.7)).frame(width: max(0, freeW))
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .frame(height: 16)

                            // Legend with percentages
                            let total = max(1.0, Double(dashboardVM.memorySnapshot.totalPhysicalBytes))
                            HStack(spacing: 10) {
                                LegendItem(color: .blue, label: "活躍", value: "\(formatMemory(dashboardVM.memorySnapshot.activeBytes)) (\(String(format: "%.1f%%", Double(dashboardVM.memorySnapshot.activeBytes) / total * 100)))")
                                LegendItem(color: .red, label: "聯動", value: "\(formatMemory(dashboardVM.memorySnapshot.wiredBytes)) (\(String(format: "%.1f%%", Double(dashboardVM.memorySnapshot.wiredBytes) / total * 100)))")
                                LegendItem(color: .purple, label: "壓縮", value: "\(formatMemory(dashboardVM.memorySnapshot.compressedBytes)) (\(String(format: "%.1f%%", Double(dashboardVM.memorySnapshot.compressedBytes) / total * 100)))")
                                LegendItem(color: .orange, label: "非活躍", value: "\(formatMemory(dashboardVM.memorySnapshot.inactiveBytes)) (\(String(format: "%.1f%%", Double(dashboardVM.memorySnapshot.inactiveBytes) / total * 100)))")
                                LegendItem(color: .green, label: "可用", value: "\(formatMemory(dashboardVM.memorySnapshot.freeBytes)) (\(String(format: "%.1f%%", Double(dashboardVM.memorySnapshot.freeBytes) / total * 100)))")
                            }
                            .font(.system(size: 11))
                        }
                    }
                }

                // Top Memory Hogs Table
                GlassCard(title: "記憶體佔用排行榜", iconName: "shippingbox.fill", accentColor: .indigo) {
                    VStack(spacing: 8) {
                        let sortedByMem = dashboardVM.processes.sorted { $0.memoryBytes > $1.memoryBytes }
                        let top8 = Array(sortedByMem.prefix(8))
                        let top8Bytes = top8.reduce(0 as UInt64) { $0 + $1.memoryBytes }
                        let totalProcBytes = sortedByMem.reduce(0 as UInt64) { $0 + $1.memoryBytes }
                        let remainingProcBytes = totalProcBytes > top8Bytes ? totalProcBytes - top8Bytes : 0

                        ForEach(top8) { proc in
                            HStack(spacing: 12) {
                                Image(systemName: proc.category.iconName)
                                    .font(.system(size: 16))
                                    .foregroundColor(proc.isUserApp ? .purple : .secondary)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(proc.name)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text("[\(proc.category.rawValue)]")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    Text("PID \(proc.pid) • \(proc.rawName)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatMemory(proc.memoryBytes))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    Text(String(format: "%.1f%% of RAM", proc.memoryPercentage))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 140, alignment: .trailing)

                                Button {
                                    dashboardVM.terminateProcess(pid: proc.pid)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("結束行程：\(proc.terminationImpact)")
                            }
                            .padding(.vertical, 4)

                            // Docker Containers Breakdown
                            if (proc.rawName.contains("docker") || proc.name.contains("Docker")) && !dashboardVM.dockerContainers.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Image(systemName: "cube.fill")
                                            .font(.system(size: 11))
                                            .foregroundColor(.blue)
                                        Text("🐳 容器個別記憶體佔用細項 (\(dashboardVM.dockerContainers.count) 個容器)：")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.blue)
                                        Spacer()
                                    }
                                    .padding(.top, 2)

                                    ForEach(dashboardVM.dockerContainers) { c in
                                        HStack(spacing: 8) {
                                            Image(systemName: "shippingbox.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(.blue.opacity(0.8))
                                            Text(c.name)
                                                .font(.system(size: 11, weight: .medium))
                                                .lineLimit(1)
                                            Spacer()
                                            Text("CPU \(String(format: "%.1f%%", c.cpuPercentage))")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text(c.memoryUsage)
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundColor(.primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.08))
                                        .cornerRadius(6)
                                    }
                                }
                                .padding(.leading, 32)
                                .padding(.vertical, 4)
                            }

                            Divider()
                        }

                        // Remaining Processes & System Memory Breakdown Summary
                        VStack(alignment: .leading, spacing: 8) {
                            Text("📊 總記憶體構成拆解說明：")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack {
                                Text("• 排行榜前 8 名應用合計:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMemory(top8Bytes)).bold()
                            }

                            HStack {
                                Text("• 其餘 \(max(0, sortedByMem.count - 8)) 個背景行程/服務合計:")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMemory(remainingProcBytes)).bold()
                            }

                            HStack {
                                Text("• 系統核心聯動 (Wired / GPU 顯存不可換出):")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMemory(dashboardVM.memorySnapshot.wiredBytes)).bold()
                            }

                            HStack {
                                Text("• 記憶體壓縮池 (Compressed / 已在 RAM 內高倍壓縮):")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(formatMemory(dashboardVM.memorySnapshot.compressedBytes)).bold()
                            }

                            if dashboardVM.memorySnapshot.swapUsedBytes > 0 {
                                HStack {
                                    Text("• SSD 虛擬交換空間 (Swap 換出至硬碟):")
                                        .foregroundColor(.orange)
                                    Spacer()
                                    Text(String(format: "%.2f GB (已換出至 SSD)", Double(dashboardVM.memorySnapshot.swapUsedBytes) / (1024*1024*1024)))
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .font(.system(size: 11))
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)
                    }
                }
            }
            .padding(20)
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label):")
                .foregroundColor(.secondary)
            Text(value)
                .bold()
        }
    }
}
