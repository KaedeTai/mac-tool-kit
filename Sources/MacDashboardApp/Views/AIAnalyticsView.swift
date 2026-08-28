import SwiftUI
import MacToolKitCore

public struct AIAnalyticsView: View {
    @ObservedObject var viewModel: AIAnalyticsViewModel
    @State private var selectedTabSection: Int = 0

    public init(viewModel: AIAnalyticsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Status Banner
                if let msg = viewModel.statusMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(8)
                }

                // MARK: - 1. Top Metrics Summary Row
                HStack(spacing: 14) {
                    MetricStatCard(
                        title: "運作中 Session",
                        value: "\(viewModel.summary.activeSessions.count)",
                        subValue: "\(viewModel.summary.totalSessionsCount) 個歷史紀錄",
                        iconName: "bolt.horizontal.fill",
                        color: viewModel.summary.activeSessions.isEmpty ? .secondary : .green
                    )

                    MetricStatCard(
                        title: "今日 Token 消耗",
                        value: viewModel.formatTokens(viewModel.summary.totalTokensToday),
                        subValue: "預估成本: \(viewModel.formatCost(viewModel.summary.totalCostUSDToday))",
                        iconName: "brain.head.profile",
                        color: .purple
                    )

                    MetricStatCard(
                        title: "累計 AI 輔助編程時長",
                        value: formatHours(viewModel.summary.totalDurationSeconds),
                        subValue: "橫跨 \(viewModel.summary.topProjects.count) 個專案",
                        iconName: "clock.arrow.circlepath",
                        color: .blue
                    )

                    MetricStatCard(
                        title: "累計總 Token 與開銷",
                        value: viewModel.formatTokens(viewModel.summary.totalTokensAllTime),
                        subValue: "總花費: \(viewModel.formatCost(viewModel.summary.totalCostUSDAllTime))",
                        iconName: "dollarsign.circle.fill",
                        color: .orange
                    )
                }

                // MARK: - 2. Active Sessions Live Banner
                if !viewModel.summary.activeSessions.isEmpty {
                    GlassCard(title: "🟢 正在運作中 AI Session (Live Active)", iconName: "bolt.fill", accentColor: .green) {
                        VStack(spacing: 10) {
                            ForEach(viewModel.summary.activeSessions) { session in
                                HStack(spacing: 14) {
                                    Image(systemName: session.toolType.iconName)
                                        .font(.system(size: 18))
                                        .foregroundColor(.green)
                                        .frame(width: 28, height: 28)
                                        .background(Color.green.opacity(0.15))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(session.toolType.rawValue)
                                                .font(.system(size: 13, weight: .bold))

                                            Text("📁 \(session.projectName)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)

                                            if let branch = session.gitBranch {
                                                Text("🌿 \(branch)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }

                                            // Status Pill
                                            Text(session.status.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.15))
                                                .foregroundColor(.green)
                                                .cornerRadius(4)
                                        }

                                        HStack(spacing: 8) {
                                            if let pid = session.livePID {
                                                Text("PID \(pid)")
                                                    .font(.system(size: 11, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }
                                            if let cpu = session.liveCPU {
                                                Text("• CPU \(String(format: "%.1f%%", cpu))")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(cpu > 50 ? .red : .primary)
                                            }
                                            if let ram = session.liveMemoryBytes {
                                                Text("• RAM \(formatMemory(ram))")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                            Text("• 已運作 \(session.formattedDuration)")
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    // Action buttons
                                    HStack(spacing: 8) {
                                        Button {
                                            viewModel.openWorkspace(path: session.projectPath)
                                        } label: {
                                            Label("工作區", systemImage: "folder")
                                                .font(.system(size: 11))
                                        }
                                        .buttonStyle(.bordered)

                                        if let pid = session.livePID {
                                            Button(role: .destructive) {
                                                viewModel.terminateSession(pid: pid)
                                            } label: {
                                                Label("中止 Session", systemImage: "stop.circle.fill")
                                                    .font(.system(size: 11))
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.red)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.green.opacity(0.06))
                                .cornerRadius(10)
                            }
                        }
                    }
                }

                // MARK: - 3. Master-Detail Session & Task Inspector
                GlassCard(title: "🔍 AI Session 深度工作分析與 Token 矩陣", iconName: "chart.bar.doc.horizontal.fill", accentColor: .purple) {
                    VStack(spacing: 12) {
                        // Filter & Currency Bar
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("搜尋專案、Session ID 或模型...", text: $viewModel.searchText)
                                    .textFieldStyle(.plain)
                            }
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)

                            // Tool Type Filter
                            Picker("工具", selection: $viewModel.filterToolType) {
                                Text("全部工具").tag(AIToolType?.none)
                                ForEach(AIToolType.allCases) { tool in
                                    Text(tool.rawValue).tag(AIToolType?.some(tool))
                                }
                            }
                            .frame(width: 140)

                            // Currency Switcher
                            Picker("幣別", selection: $viewModel.selectedCurrency) {
                                ForEach(CurrencyMode.allCases) { cur in
                                    Text(cur.rawValue).tag(cur)
                                }
                            }
                            .frame(width: 120)

                            Button {
                                viewModel.refreshData()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                            }
                            .buttonStyle(.plain)
                            .help("手動重新整理 Session 數據")
                        }

                        Divider()

                        // Two Column Master-Detail
                        HStack(alignment: .top, spacing: 14) {
                            // Left: Session List (Master)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("最近 Session 列表 (\(viewModel.filteredSessions.count))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                ScrollView {
                                    LazyVStack(spacing: 6) {
                                        ForEach(viewModel.filteredSessions) { s in
                                            let isSelected = viewModel.selectedSession?.sessionId == s.sessionId
                                            Button {
                                                viewModel.selectedSession = s
                                            } label: {
                                                HStack(spacing: 10) {
                                                    Image(systemName: s.toolType.iconName)
                                                        .foregroundColor(isSelected ? .white : .purple)
                                                        .frame(width: 18)

                                                    VStack(alignment: .leading, spacing: 2) {
                                                        HStack {
                                                            Text(s.projectName)
                                                                .font(.system(size: 12, weight: .bold))
                                                                .foregroundColor(isSelected ? .white : .primary)
                                                                .lineLimit(1)
                                                            Spacer()
                                                            Text(viewModel.formatCost(s.estimatedCostUSD))
                                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                                .foregroundColor(isSelected ? .white : .purple)
                                                        }

                                                        HStack {
                                                            Text("#\(s.sessionShortId)")
                                                                .font(.system(size: 10, design: .monospaced))
                                                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                                            Spacer()
                                                            Text("\(viewModel.formatTokens(s.tokenUsage.totalTokens)) 記號 • \(s.formattedDuration)")
                                                                .font(.system(size: 10))
                                                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                                        }
                                                    }
                                                }
                                                .padding(8)
                                                .background(isSelected ? Color.purple : Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                                .cornerRadius(8)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                                .frame(height: 460)
                            }
                            .frame(width: 290)

                            Divider()

                            // Right: Detail Inspector
                            if let session = viewModel.selectedSession {
                                SessionDetailInspectorView(session: session, viewModel: viewModel)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("請從左側選擇一個 AI Session 進行深度分析")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }
                }

                // MARK: - 4. Project Rankings & Global Breakdown
                HStack(spacing: 14) {
                    // Top Projects
                    GlassCard(title: "🏆 各專案 AI 開銷與 Token 排行", iconName: "folder.fill", accentColor: .blue) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.summary.topProjects.prefix(6)) { proj in
                                HStack {
                                    Text(proj.projectName)
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                    Text("\(proj.sessionCount) 次 Session")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(viewModel.formatTokens(proj.totalTokens))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(viewModel.formatCost(proj.totalCostUSD))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.blue)
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                                Divider()
                            }
                        }
                    }

                    // Global Models Used
                    GlassCard(title: "🤖 全域模型調用分佈", iconName: "cpu.fill", accentColor: .indigo) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.summary.allModelsUsed.prefix(6)) { m in
                                HStack {
                                    Text(m.modelName)
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                    Text("\(m.turnCount) 次調用")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                    Text(viewModel.formatTokens(m.inputTokens + m.outputTokens + m.cacheReadTokens))
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                    Text(viewModel.formatCost(m.estimatedCostUSD))
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.indigo)
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.vertical, 3)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func formatHours(_ seconds: TimeInterval) -> String {
        let hours = seconds / 3600.0
        if hours < 0.1 {
            return "\(Int(seconds / 60)) 分鐘"
        }
        return String(format: "%.1f 小時", hours)
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
    }
}

// MARK: - Subviews
struct MetricStatCard: View {
    let title: String
    let value: String
    let subValue: String
    let iconName: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subValue)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }
}

struct SessionDetailInspectorView: View {
    let session: AISessionRecord
    @ObservedObject var viewModel: AIAnalyticsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header Info
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(session.projectName)
                                .font(.system(size: 16, weight: .bold))
                            if let b = session.gitBranch {
                                Text("🌿 \(b)")
                                    .font(.system(size: 11, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            }
                        }
                        Text("Session ID: \(session.sessionId)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(viewModel.formatCost(session.estimatedCostUSD))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text("總計 \(viewModel.formatTokens(session.tokenUsage.totalTokens)) Tokens")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // 1. Models Used
                VStack(alignment: .leading, spacing: 6) {
                    Text("🧠 調用模型與開銷分佈 (Models Used)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach(session.modelsUsed) { m in
                        HStack {
                            Text("• \(m.modelName)")
                                .font(.system(size: 12, weight: .semibold))
                            Spacer()
                            Text("\(m.turnCount) Turns")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(viewModel.formatTokens(m.inputTokens + m.outputTokens + m.cacheReadTokens))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(viewModel.formatCost(m.estimatedCostUSD))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(6)
                        .background(Color.purple.opacity(0.06))
                        .cornerRadius(6)
                    }
                }

                // 2. Task Category Breakdown
                VStack(alignment: .leading, spacing: 6) {
                    Text("📋 工作類型與 Token 佔比 (Tasks Breakdown)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    ForEach(session.taskBreakdown) { t in
                        HStack {
                            Image(systemName: t.category.iconName)
                                .font(.system(size: 11))
                                .foregroundColor(.blue)
                                .frame(width: 16)
                            Text(t.category.rawValue)
                                .font(.system(size: 11, weight: .medium))
                            Spacer()
                            Text("\(t.callCount) 次")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%% 開銷", t.tokenShare * 100))
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                            Text(viewModel.formatCost(t.estimatedCostUSD))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.blue)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(6)
                        .background(Color.blue.opacity(0.06))
                        .cornerRadius(6)
                    }
                }

                // 3. Token Granular Structure
                VStack(alignment: .leading, spacing: 6) {
                    Text("🪙 Token 結構明細")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        TokenBadge(label: "輸入 (Input)", value: viewModel.formatTokens(session.tokenUsage.inputTokens), color: .blue)
                        TokenBadge(label: "生成 (Output)", value: viewModel.formatTokens(session.tokenUsage.outputTokens), color: .green)
                        TokenBadge(label: "快取命中 (Cache)", value: viewModel.formatTokens(session.tokenUsage.cacheReadTokens), color: .purple)
                        if session.tokenUsage.thinkingTokens > 0 {
                            TokenBadge(label: "思考 (Thinking)", value: viewModel.formatTokens(session.tokenUsage.thinkingTokens), color: .orange)
                        }
                    }
                }

                // 4. Chronological Turns Timeline
                if !session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("⏱️ 對話與任務時間軸 (Chronological Turns: \(session.turns.count))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        LazyVStack(spacing: 6) {
                            ForEach(session.turns.prefix(20)) { turn in
                                HStack(spacing: 8) {
                                    Text("#\(turn.turnIndex)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .leading)

                                    Image(systemName: turn.taskCategory.iconName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.purple)

                                    Text(turn.taskDescription)
                                        .font(.system(size: 11))
                                        .lineLimit(1)

                                    Spacer()

                                    if let m = turn.modelName {
                                        Text(m.replacingOccurrences(of: "claude-", with: ""))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }

                                    Text(viewModel.formatTokens(turn.inputTokens + turn.outputTokens + turn.cacheReadTokens))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                .padding(6)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                                .cornerRadius(6)
                            }
                        }
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 460)
    }
}

struct TokenBadge: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }
}
