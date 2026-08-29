import SwiftUI
import MacToolKitCore

public struct MenuBarView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var lagVM: LagDetectiveViewModel
    @ObservedObject var fanVM: FanControlViewModel
    let openMainWindow: () -> Void

    public var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundColor(.accentColor)
                Text("Mac 運作監控")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                StatBadge(
                    text: dashboardVM.batteryThermalSnapshot.thermalState.rawValue,
                    color: dashboardVM.batteryThermalSnapshot.thermalState == .nominal ? .green : .orange
                )
            }

            Divider()

            // Resource Dials
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f%%", dashboardVM.cpuSnapshot.totalUsage))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(dashboardVM.cpuSnapshot.totalUsage > 70 ? .red : .primary)
                    Text("CPU 負載")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text(String(format: "%.1f%%", dashboardVM.memorySnapshot.usedPercentage))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(dashboardVM.memorySnapshot.usedPercentage > 85 ? .red : .primary)
                    Text("RAM 佔用")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Divider().frame(height: 30)

                VStack(spacing: 4) {
                    Text(dashboardVM.fanStatuses.first.map { "\($0.currentRPM)" } ?? "N/A")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.blue)
                    Text("風扇 RPM")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)

            Divider()

            // Top CPU Process
            if let top = dashboardVM.filteredProcesses.first {
                HStack {
                    Text("最高耗能:")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(top.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%.1f%%", top.cpuPercentage))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(top.cpuPercentage > 50 ? .red : .primary)
                }
            }

            // Quick Actions
            HStack(spacing: 8) {
                Button {
                    fanVM.selectMode(.maxCooling)
                } label: {
                    Label("全速散熱", systemImage: "snowflake")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            // Open Window / Quit
            HStack {
                Button {
                    openMainWindow()
                } label: {
                    Text("打開完整監控臺...")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Text("結束")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 290)
    }
}
