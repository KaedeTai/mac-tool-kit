import SwiftUI
import MacToolKitCore

public struct CPUView: View {
    @ObservedObject var dashboardVM: DashboardViewModel

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 150), spacing: 12)
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Stats
                HStack(spacing: 16) {
                    GlassCard(title: "處理器核心總覽", iconName: "cpu", accentColor: .blue) {
                        HStack(spacing: 24) {
                            CircularGaugeView(
                                percentage: dashboardVM.cpuSnapshot.totalUsage,
                                title: "總 CPU 負載",
                                subtitle: "\(dashboardVM.cpuSnapshot.physicalCores) 實體 / \(dashboardVM.cpuSnapshot.logicalCores) 邏輯",
                                iconName: "cpu.fill",
                                size: 110
                            )

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("使用者進程 (User):").foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", dashboardVM.cpuSnapshot.userUsage)).bold()
                                }
                                HStack {
                                    Text("系統核心 (System):").foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", dashboardVM.cpuSnapshot.systemUsage)).bold()
                                }
                                HStack {
                                    Text("閒置資源 (Idle):").foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.1f%%", dashboardVM.cpuSnapshot.idleUsage)).foregroundColor(.secondary)
                                }

                                SparklineView(data: dashboardVM.cpuHistory, lineColor: .blue)
                                    .frame(height: 45)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }

                // Per Core Visualizer
                GlassCard(title: "各核心即時負載分佈 (Per-Core Loads)", iconName: "square.grid.3x3.fill", accentColor: .cyan) {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(dashboardVM.cpuSnapshot.cores) { core in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Core \(core.coreNumber)")
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                    Text(core.isPerformanceCore ? "P-Core" : "E-Core")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(core.isPerformanceCore ? Color.orange.opacity(0.2) : Color.blue.opacity(0.2))
                                        .foregroundColor(core.isPerformanceCore ? .orange : .blue)
                                        .cornerRadius(4)
                                }

                                ProgressView(value: core.totalUsage, total: 100.0)
                                    .tint(coreColor(for: core.totalUsage))

                                Text(String(format: "%.1f%%", core.totalUsage))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(core.totalUsage > 75 ? .red : .primary)
                            }
                            .padding(10)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(10)
                        }
                    }
                }

                // Process Table for CPU
                GlassCard(title: "CPU 佔用排行榜", iconName: "flame.fill", accentColor: .orange) {
                    VStack(spacing: 8) {
                        ForEach(dashboardVM.filteredProcesses.prefix(8)) { proc in
                            HStack(spacing: 12) {
                                Image(systemName: proc.isUserApp ? "app.badge.fill" : "gearshape.2")
                                    .font(.system(size: 16))
                                    .foregroundColor(proc.isUserApp ? .blue : .secondary)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(proc.name)
                                        .font(.system(size: 13, weight: .medium))
                                    Text("PID: \(proc.pid) • \(proc.threadCount) Threads")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(String(format: "%.1f%%", proc.cpuPercentage))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(proc.cpuPercentage > 60 ? .red : (proc.cpuPercentage > 20 ? .orange : .primary))
                                    Text("\(formatMemory(proc.memoryBytes)) (\(String(format: "%.1f%%", proc.memoryPercentage)))")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 120, alignment: .trailing)

                                Button {
                                    dashboardVM.terminateProcess(pid: proc.pid)
                                } label: {
                                    Image(systemName: "xmark.circle")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .help("強制結束此行程")
                            }
                            .padding(.vertical, 4)

                            if proc.id != dashboardVM.filteredProcesses.prefix(8).last?.id {
                                Divider()
                            }
                        }
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

    private func coreColor(for usage: Double) -> Color {
        if usage < 50 {
            return .green
        } else if usage < 80 {
            return .orange
        } else {
            return .red
        }
    }
}
