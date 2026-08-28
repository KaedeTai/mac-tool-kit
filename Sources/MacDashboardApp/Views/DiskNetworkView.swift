import SwiftUI
import MacToolKitCore

public struct DiskNetworkView: View {
    @ObservedObject var dashboardVM: DashboardViewModel

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Disk Volumes
                GlassCard(title: "磁碟與儲存空間 (Volumes)", iconName: "internaldrive.fill", accentColor: .orange) {
                    VStack(spacing: 16) {
                        ForEach(dashboardVM.diskVolumes) { vol in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 16))
                                        .foregroundColor(.orange)
                                    Text(vol.name)
                                        .font(.system(size: 14, weight: .bold))
                                    Text("(\(vol.path))")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.1f", vol.usedPercentage))% 已使用")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(vol.usedPercentage > 85 ? .red : .primary)
                                }

                                ProgressView(value: vol.usedPercentage, total: 100.0)
                                    .tint(vol.usedPercentage > 85 ? .red : (vol.usedPercentage > 70 ? .orange : .blue))

                                HStack {
                                    Text("可用空間: \(formatBytes(vol.freeBytes))")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text("已使用: \(formatBytes(vol.usedBytes)) / 總計: \(formatBytes(vol.totalBytes))")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(10)
                        }

                        Divider()

                        // Disk I/O Speeds
                        HStack(spacing: 24) {
                            HStack(spacing: 12) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("磁碟讀取速率")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text(formatSpeed(dashboardVM.diskIOSnapshot.readBytesPerSec))
                                        .font(.title3.bold())
                                }
                            }

                            Spacer()

                            HStack(spacing: 12) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("磁碟寫入速率")
                                        .font(.caption).foregroundColor(.secondary)
                                    Text(formatSpeed(dashboardVM.diskIOSnapshot.writeBytesPerSec))
                                        .font(.title3.bold())
                                }
                            }
                        }
                    }
                }

                // Network Throughput
                GlassCard(title: "即時網路頻寬傳輸 (Network Bandwidth)", iconName: "network", accentColor: .teal) {
                    VStack(spacing: 16) {
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "arrow.down.forward.circle.fill")
                                        .foregroundColor(.teal)
                                    Text("下載即時速度:")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatSpeed(dashboardVM.networkIOSnapshot.downloadBytesPerSec))
                                        .font(.headline.bold())
                                }

                                SparklineView(data: dashboardVM.networkDownHistory, lineColor: .teal, fillColor: .teal.opacity(0.2))
                                    .frame(height: 60)
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(10)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "arrow.up.forward.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("上傳即時速度:")
                                        .font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatSpeed(dashboardVM.networkIOSnapshot.uploadBytesPerSec))
                                        .font(.headline.bold())
                                }

                                SparklineView(data: dashboardVM.networkUpHistory, lineColor: .blue, fillColor: .blue.opacity(0.2))
                                    .frame(height: 60)
                            }
                            .padding(12)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .cornerRadius(10)
                        }

                        HStack {
                            Text("累計下載流量: \(formatBytes(dashboardVM.networkIOSnapshot.totalDownloadBytes))")
                                .font(.caption).foregroundColor(.secondary)
                            Spacer()
                            Text("累計上傳流量: \(formatBytes(dashboardVM.networkIOSnapshot.totalUploadBytes))")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1.0 {
            return String(format: "%.1f GB", gb)
        } else {
            return String(format: "%.0f MB", Double(bytes) / (1024 * 1024))
        }
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytesPerSec / (1024 * 1024))
        } else {
            return String(format: "%.1f KB/s", bytesPerSec / 1024)
        }
    }
}
