import SwiftUI
import MacToolKitCore

public struct DiskNetworkView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @State private var isShowingCleanup = false

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                volumeCard
                compositionCard
                reclaimCard
                networkCard
            }
            .padding(20)
        }
        .task {
            await dashboardVM.refreshStorageAnalysis()
        }
        .sheet(isPresented: $isShowingCleanup) {
            StorageCleanupSelectionSheet(
                candidates: visibleCleanupCandidates,
                isCleaning: dashboardVM.isStorageCleanupRunning
            ) { selectedIDs in
                Task {
                    await dashboardVM.cleanStorage(candidateIDs: selectedIDs)
                }
            }
        }
    }

    private var volumeCard: some View {
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
                                .lineLimit(1)
                            Spacer(minLength: 12)
                            Text("\(String(format: "%.1f", vol.usedPercentage))% 已使用")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(vol.usedPercentage > 85 ? .red : .primary)
                        }

                        ProgressView(value: vol.usedPercentage, total: 100.0)
                            .tint(vol.usedPercentage > 85 ? .red : (vol.usedPercentage > 70 ? .orange : .blue))

                        ViewThatFits(in: .horizontal) {
                            HStack {
                                Text("可用空間：\(formatBytes(vol.freeBytes))")
                                Spacer()
                                Text("已使用：\(formatBytes(vol.usedBytes)) / 總計：\(formatBytes(vol.totalBytes))")
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text("可用空間：\(formatBytes(vol.freeBytes))")
                                Text("已使用：\(formatBytes(vol.usedBytes)) / 總計：\(formatBytes(vol.totalBytes))")
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .cornerRadius(10)
                }

                Divider()

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        diskRate(icon: "arrow.down.circle.fill", title: "磁碟讀取速率", value: dashboardVM.diskIOSnapshot.readBytesPerSec, color: .green)
                        Spacer()
                        diskRate(icon: "arrow.up.circle.fill", title: "磁碟寫入速率", value: dashboardVM.diskIOSnapshot.writeBytesPerSec, color: .orange)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        diskRate(icon: "arrow.down.circle.fill", title: "磁碟讀取速率", value: dashboardVM.diskIOSnapshot.readBytesPerSec, color: .green)
                        diskRate(icon: "arrow.up.circle.fill", title: "磁碟寫入速率", value: dashboardVM.diskIOSnapshot.writeBytesPerSec, color: .orange)
                    }
                }
            }
        }
    }

    private var compositionCard: some View {
        GlassCard(title: "檔案容量組成（實測掃描）", iconName: "chart.bar.xaxis", accentColor: .blue) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("掃描具名的使用者資料夾；檔名與內容不會離開這台 Mac。")
                            .font(.system(size: 12, weight: .medium))
                        if dashboardVM.storageAnalysis.scannedAt != .distantPast {
                            Text("來源：本機檔案系統配置區塊（不讀取檔案內容） · 最後掃描 \(dashboardVM.storageAnalysis.scannedAt.formatted(date: .omitted, time: .standard))")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Button {
                        Task { await dashboardVM.refreshStorageAnalysis(force: true) }
                    } label: {
                        Label("重新掃描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(dashboardVM.isStorageAnalysisRunning || dashboardVM.isStorageCleanupRunning)
                }

                if dashboardVM.isStorageAnalysisRunning && dashboardVM.storageAnalysis.categories.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在背景量測常用資料夾；不會加入每秒監控…")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                } else if measuredCategories.isEmpty {
                    Text("尚未取得可呈現的使用者檔案容量。請重新掃描；權限不足的資料不會用估算補上。")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 22) {
                            compositionMetric(title: "具名分類實測", bytes: measuredCategoryBytes, color: .blue)
                            compositionMetric(title: "磁碟已使用", bytes: dashboardVM.storageAnalysis.volumeUsedBytes, color: .orange)
                            compositionMetric(title: "未分類", bytes: unclassifiedUsedBytes, color: .secondary)
                            Spacer()
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            compositionMetric(title: "具名分類實測", bytes: measuredCategoryBytes, color: .blue)
                            compositionMetric(title: "磁碟已使用", bytes: dashboardVM.storageAnalysis.volumeUsedBytes, color: .orange)
                            compositionMetric(title: "未分類", bytes: unclassifiedUsedBytes, color: .secondary)
                        }
                    }

                    GeometryReader { geo in
                        HStack(spacing: 2) {
                            ForEach(measuredCategories) { category in
                                Rectangle()
                                    .fill(categoryColor(category.id))
                                    .frame(width: segmentWidth(category.allocatedBytes, totalWidth: geo.size.width))
                            }
                            if unclassifiedUsedBytes > 0 {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.35))
                                    .frame(width: segmentWidth(unclassifiedUsedBytes, totalWidth: geo.size.width))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .frame(height: 18)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 9) {
                        ForEach(measuredCategories) { category in
                            HStack(alignment: .top, spacing: 7) {
                                Circle()
                                    .fill(categoryColor(category.id))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(category.title) · \(formatBytes(category.allocatedBytes))")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("\(category.fileCount.formatted()) 個檔案\(category.isComplete ? "" : " · 部分可讀")")
                                        .font(.system(size: 9))
                                        .foregroundColor(category.isComplete ? .secondary : .orange)
                                }
                            }
                            .help(category.sourcePaths.joined(separator: "\n"))
                        }

                        if unclassifiedUsedBytes > 0 {
                            HStack(alignment: .top, spacing: 7) {
                                Circle().fill(Color.secondary.opacity(0.35)).frame(width: 8, height: 8).padding(.top, 4)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("系統、其他使用者與未掃描 · \(formatBytes(unclassifiedUsedBytes))")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("由磁碟已使用量扣除上方實測分類；不推測內容")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    if incompleteCategoryCount > 0 {
                        Label(
                            "\(incompleteCategoryCount) 個分類受權限或缺少路徑影響；顯示值只是成功讀取部分的下限。",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                    }
                }
            }
        }
    }

    private var reclaimCard: some View {
        GlassCard(title: "可釋放空間（先選擇影響範圍）", iconName: "sparkles", accentColor: .pink) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("可勾選項目掃描值：\(formatBytes(selectableCleanupBytes))")
                            .font(.system(size: 13, weight: .bold))
                        Text("預設不勾任何項目；實際結果只在清理後重新量測。")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        isShowingCleanup = true
                    } label: {
                        Label("選擇並釋放空間…", systemImage: "checklist")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.pink)
                    .disabled(
                        dashboardVM.isStorageAnalysisRunning ||
                        dashboardVM.isStorageCleanupRunning ||
                        visibleCleanupCandidates.isEmpty
                    )
                }

                if dashboardVM.isStorageCleanupRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在清理所選項目並重新量測…")
                    }
                    .font(.system(size: 11, weight: .medium))
                }

                if let result = dashboardVM.storageCleanupResult {
                    cleanupResultView(result)
                }

                Divider()

                if let docker = dashboardVM.storageAnalysis.docker {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Docker 儲存由 Docker 管理", systemImage: "shippingbox.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.blue)
                            Spacer()
                            Text("來源：docker system df")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .leading)], alignment: .leading, spacing: 8) {
                            ForEach(docker.items) { item in
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(dockerTitle(item.kind))
                                            .font(.system(size: 11, weight: .semibold))
                                        Spacer()
                                        Text("可回收 \(formatBytesDecimal(item.reclaimableBytes))")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(item.requiresExplicitVolumeDeletion ? .red : .blue)
                                    }
                                    Text("總量 \(formatBytesDecimal(item.sizeBytes)) · \(item.activeCount)/\(item.totalCount) active")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                                .padding(9)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                                .cornerRadius(8)
                            }
                        }

                        Text("請先在 Docker Desktop 的 Images／Containers／Volumes 檢查影響。`docker system prune -a` 可清未使用映像、已停止容器、網路與 build cache，但不含 volumes；`docker volume prune` 可能永久刪除資料庫，因此 Dashboard 不提供此動作。")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(11)
                    .background(Color.blue.opacity(0.07))
                    .cornerRadius(10)
                } else {
                    Text("Docker 未執行或無法讀取時，不顯示可回收量；Dashboard 不會自行猜測 Docker VM 檔案中哪些資料可刪。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var networkCard: some View {
        GlassCard(title: "即時網路頻寬傳輸 (Network Bandwidth)", iconName: "network", accentColor: .teal) {
            VStack(spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) {
                        networkRatePanel(icon: "arrow.down.forward.circle.fill", title: "下載即時速度", value: dashboardVM.networkIOSnapshot.downloadBytesPerSec, history: dashboardVM.networkDownHistory, color: .teal)
                        networkRatePanel(icon: "arrow.up.forward.circle.fill", title: "上傳即時速度", value: dashboardVM.networkIOSnapshot.uploadBytesPerSec, history: dashboardVM.networkUpHistory, color: .blue)
                    }
                    VStack(spacing: 12) {
                        networkRatePanel(icon: "arrow.down.forward.circle.fill", title: "下載即時速度", value: dashboardVM.networkIOSnapshot.downloadBytesPerSec, history: dashboardVM.networkDownHistory, color: .teal)
                        networkRatePanel(icon: "arrow.up.forward.circle.fill", title: "上傳即時速度", value: dashboardVM.networkIOSnapshot.uploadBytesPerSec, history: dashboardVM.networkUpHistory, color: .blue)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text("介面自開機累計下載（64-bit）：\(formatBytes(dashboardVM.networkIOSnapshot.totalDownloadBytes))")
                        Spacer()
                        Text("介面自開機累計上傳（64-bit）：\(formatBytes(dashboardVM.networkIOSnapshot.totalUploadBytes))")
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("介面自開機累計下載（64-bit）：\(formatBytes(dashboardVM.networkIOSnapshot.totalDownloadBytes))")
                        Text("介面自開機累計上傳（64-bit）：\(formatBytes(dashboardVM.networkIOSnapshot.totalUploadBytes))")
                    }
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var measuredCategories: [StorageCategorySnapshot] {
        dashboardVM.storageAnalysis.categories.filter { $0.allocatedBytes > 0 }.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    private var measuredCategoryBytes: UInt64 {
        measuredCategories.reduce(0) { $0 + $1.allocatedBytes }
    }

    private var unclassifiedUsedBytes: UInt64 {
        StorageCompositionMath.unclassifiedUsedBytes(
            volumeUsedBytes: dashboardVM.storageAnalysis.volumeUsedBytes,
            measuredCategoryBytes: measuredCategories.map(\.allocatedBytes)
        )
    }

    private var compositionDenominator: UInt64 {
        max(1, max(dashboardVM.storageAnalysis.volumeUsedBytes, measuredCategoryBytes))
    }

    private var incompleteCategoryCount: Int {
        dashboardVM.storageAnalysis.categories.filter { !$0.isComplete }.count
    }

    private var visibleCleanupCandidates: [StorageCleanupCandidate] {
        dashboardVM.storageAnalysis.cleanupCandidates.filter { candidate in
            if candidate.measuredBytes > 0 { return true }
            if candidate.id == "trash" {
                return !candidate.notes.contains(where: { $0.contains("不存在") })
            }
            return false
        }
    }

    private var selectableCleanupBytes: UInt64 {
        visibleCleanupCandidates.filter(\.isSelectable).reduce(0) { $0 + $1.measuredBytes }
    }

    @ViewBuilder
    private func diskRate(icon: String, title: String, value: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title2).foregroundColor(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundColor(.secondary)
                Text(formatSpeed(value)).font(.title3.bold())
            }
        }
    }

    @ViewBuilder
    private func compositionMetric(title: String, bytes: UInt64, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text(formatBytes(bytes)).font(.system(size: 15, weight: .bold)).foregroundColor(color)
        }
    }

    @ViewBuilder
    private func networkRatePanel(icon: String, title: String, value: Double, history: [Double], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundColor(color)
                Text("\(title)：").font(.caption).foregroundColor(.secondary)
                Spacer()
                Text(formatSpeed(value)).font(.headline.bold())
            }
            SparklineView(data: history, lineColor: color, fillColor: color.opacity(0.2)).frame(height: 60)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(10)
    }

    @ViewBuilder
    private func cleanupResultView(_ result: StorageCleanupResult) -> some View {
        let failedCount = result.items.filter { !$0.succeeded }.count
        VStack(alignment: .leading, spacing: 4) {
            Label("項目容量減少：\(formatBytes(result.measuredItemDecreaseBytes))", systemImage: failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(failedCount == 0 ? .green : .orange)
            if let freeIncrease = result.volumeFreeIncreaseBytes {
                Text("同一磁碟可用空間增加：\(formatBytes(freeIncrease))（APFS 快照或系統快取可能讓兩者不同）")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            if failedCount > 0 || !result.rejectedIDs.isEmpty {
                Text("\(failedCount) 個項目未完整清理；\(result.rejectedIDs.count) 個非允許 ID 已拒絕。")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((failedCount == 0 ? Color.green : Color.orange).opacity(0.08))
        .cornerRadius(8)
    }

    private func segmentWidth(_ bytes: UInt64, totalWidth: CGFloat) -> CGFloat {
        totalWidth * CGFloat(Double(bytes) / Double(compositionDenominator))
    }

    private func categoryColor(_ id: String) -> Color {
        switch id {
        case "documents": return .blue
        case "downloads": return .cyan
        case "desktop": return .mint
        case "media": return .pink
        case "applications": return .indigo
        case "application-data": return .purple
        case "developer": return .orange
        case "ai-tools": return .teal
        case "caches": return .yellow
        case "logs": return .brown
        default: return .gray
        }
    }

    private func dockerTitle(_ kind: DockerDiskUsageKind) -> String {
        switch kind {
        case .images: return "映像檔 Images"
        case .containers: return "容器 Containers"
        case .volumes: return "資料卷 Volumes"
        case .buildCache: return "Build Cache"
        case .other: return "其他 Docker 資料"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 { return String(format: "%.1f GiB", gib) }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 { return String(format: "%.0f MiB", mib) }
        return String(format: "%.0f KiB", Double(bytes) / 1024)
    }

    private func formatBytesDecimal(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        return String(format: "%.0f MB", Double(bytes) / 1_000_000)
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 { return String(format: "%.1f MiB/s", bytesPerSec / 1_048_576) }
        return String(format: "%.1f KiB/s", bytesPerSec / 1024)
    }
}

private struct StorageCleanupSelectionSheet: View {
    let candidates: [StorageCleanupCandidate]
    let isCleaning: Bool
    let onConfirm: (Set<String>) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedIDs = Set<String>()
    @State private var isConfirming = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 24))
                    .foregroundColor(.pink)
                VStack(alignment: .leading, spacing: 2) {
                    Text("選擇要清理的項目").font(.system(size: 18, weight: .bold))
                    Text("沒有預設勾選；每個項目只清除下方顯示的固定路徑內容。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(18)

            Divider()

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(candidates.sorted(by: candidateSort)) { candidate in
                        Button {
                            if selectedIDs.contains(candidate.id) { selectedIDs.remove(candidate.id) }
                            else { selectedIDs.insert(candidate.id) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 17))
                                    .foregroundColor(selectedIDs.contains(candidate.id) ? .accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack(spacing: 8) {
                                        Text(candidate.title).font(.system(size: 13, weight: .bold))
                                        impactBadge(candidate.impact)
                                        Spacer()
                                        Text(candidate.measuredBytes > 0 ? "\(candidate.isComplete ? "" : "至少 ")\(formatBytes(candidate.measuredBytes))" : "無可驗證容量")
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    }
                                    Text(candidate.consequence)
                                        .font(.system(size: 11)).foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(candidate.path)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundColor(.secondary.opacity(0.8)).textSelection(.enabled)
                                    if !candidate.isSelectable, let reason = candidate.notes.first {
                                        Text(reason).font(.system(size: 10, weight: .medium)).foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        .disabled(!candidate.isSelectable || isCleaning)
                    }
                }
                .padding(18)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已選 \(selectedIDs.count) 項 · 掃描容量 \(formatBytes(selectedBytes))")
                        .font(.system(size: 12, weight: .bold))
                    Text("掃描容量不是保證釋放量；完成後會重新量測。")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .frame(minWidth: 72)
                    .keyboardShortcut(.cancelAction)
                Button("清理所選項目…", role: .destructive) { isConfirming = true }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .disabled(selectedIDs.isEmpty || isCleaning)
            }
            .padding(18)
        }
        .frame(minWidth: 620, minHeight: 520)
        .confirmationDialog("永久清除所選項目內容？", isPresented: $isConfirming, titleVisibility: .visible) {
            Button("永久清除 \(selectedIDs.count) 個項目", role: .destructive) {
                let selection = selectedIDs
                dismiss()
                onConfirm(selection)
            }
            Button("返回檢查", role: .cancel) {}
        } message: {
            Text("將清除：\(selectedTitles.joined(separator: "、"))。低影響快取可重新建立；日誌與垃圾桶內容無法由 Dashboard 復原。")
        }
    }

    private var selectedBytes: UInt64 {
        candidates.filter { selectedIDs.contains($0.id) }.reduce(0) { $0 + $1.measuredBytes }
    }

    private var selectedTitles: [String] {
        candidates.filter { selectedIDs.contains($0.id) }.map(\.title)
    }

    private func candidateSort(_ lhs: StorageCleanupCandidate, _ rhs: StorageCleanupCandidate) -> Bool {
        if lhs.impact != rhs.impact { return lhs.impact < rhs.impact }
        return lhs.measuredBytes > rhs.measuredBytes
    }

    @ViewBuilder
    private func impactBadge(_ impact: StorageCleanupImpact) -> some View {
        let color: Color = impact == .low ? .green : (impact == .medium ? .orange : .red)
        Text(impact.title)
            .font(.system(size: 9, weight: .bold)).foregroundColor(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.12)).cornerRadius(4)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gib = Double(bytes) / 1_073_741_824
        if gib >= 1 { return String(format: "%.1f GiB", gib) }
        let mib = Double(bytes) / 1_048_576
        if mib >= 1 { return String(format: "%.0f MiB", mib) }
        return String(format: "%.0f KiB", Double(bytes) / 1024)
    }
}
