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
                        subValue: "橫跨 \(viewModel.summary.projectWorkspaces.count) 個專案",
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

                                            Text("📁 \(session.parentProjectName)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(Color.blue.opacity(0.15))
                                                .foregroundColor(.blue)
                                                .cornerRadius(4)

                                            if let slug = session.subagentSlug {
                                                Text("🌿 \(slug)")
                                                    .font(.system(size: 10, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            }

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
                                            Text("• 歷時 \(session.formattedDuration)")
                                                .font(.system(size: 10))
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

                // MARK: - 3. Hierarchical Master-Detail Session & Task Inspector
                GlassCard(title: "🔍 專案資料夾、主大腦與 Subagent 工作流分析", iconName: "chart.bar.doc.horizontal.fill", accentColor: .purple) {
                    VStack(spacing: 12) {
                        // Filter & Currency Bar
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                TextField("搜尋專案、Subagent、Session ID 或模型...", text: $viewModel.searchText)
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

                        // Two Column Master-Detail Tree
                        HStack(alignment: .top, spacing: 14) {
                            // Left: Hierarchical Project Workspaces & Subagents Tree
                            VStack(alignment: .leading, spacing: 6) {
                                Text("專案架構與工作流樹狀圖 (\(viewModel.filteredWorkspaces.count) 個專案)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)

                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(viewModel.filteredWorkspaces) { ws in
                                            ProjectWorkspaceTreeCard(
                                                workspace: ws,
                                                selectedSessionId: viewModel.selectedSession?.sessionId,
                                                onSelectSession: { s in
                                                    viewModel.selectedSession = s
                                                },
                                                formatCost: viewModel.formatCost,
                                                formatTokens: viewModel.formatTokens
                                            )
                                        }
                                    }
                                }
                                .frame(height: 520)
                            }
                            .frame(width: 320)

                            Divider()

                            // Right: Detail Inspector
                            if let session = viewModel.selectedSession {
                                SessionDetailInspectorView(session: session, viewModel: viewModel)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 40))
                                        .foregroundColor(.secondary.opacity(0.5))
                                    Text("請從左側專案樹中點選一個「主大腦」或「Subagent」查看完整 Token 與工作分析")
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
                    GlassCard(title: "🏆 各專案 AI 總開銷與 Token 排行", iconName: "folder.fill", accentColor: .blue) {
                        VStack(spacing: 8) {
                            ForEach(viewModel.summary.projectWorkspaces.prefix(6)) { proj in
                                HStack {
                                    Text(proj.projectName)
                                        .font(.system(size: 12, weight: .bold))
                                    Spacer()
                                    Text("\(proj.sessionCount) 個工作流")
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

// MARK: - Tree Card Component
struct ProjectWorkspaceTreeCard: View {
    let workspace: AIProjectWorkspace
    let selectedSessionId: String?
    let onSelectSession: (AISessionRecord) -> Void
    let formatCost: (Double) -> String
    let formatTokens: (Int64) -> String

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Workspace Folder Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)

                    Image(systemName: "folder.fill")
                        .foregroundColor(.blue)

                    Text(workspace.projectName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if workspace.hasLiveActive {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(formatCost(workspace.totalCostUSD))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.purple)
                        Text(formatTokens(workspace.totalTokens))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)

            // Child Sessions & Subagents
            if isExpanded {
                VStack(spacing: 3) {
                    // 1. Main Station Sessions
                    ForEach(workspace.mainSessions) { s in
                        let isSelected = selectedSessionId == s.sessionId
                        Button {
                            onSelectSession(s)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(isSelected ? .white : .orange)
                                    .frame(width: 14)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text("主 Session (#\(s.sessionShortId))")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(isSelected ? .white : .primary)
                                        Spacer()
                                        Text(formatCost(s.estimatedCostUSD))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(isSelected ? .white : .purple)
                                    }
                                    HStack {
                                        Text("\(formatTokens(s.tokenUsage.totalTokens)) 記號 • \(s.formattedDuration)")
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                        Spacer()
                                        if s.livePID != nil {
                                            Text("🟢 Active")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .padding(.leading, 12)
                            .background(isSelected ? Color.purple : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }

                    // 2. Subagent Workflows
                    ForEach(workspace.subagentSessions) { s in
                        let isSelected = selectedSessionId == s.sessionId
                        Button {
                            onSelectSession(s)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.turn.down.right")
                                    .font(.system(size: 9))
                                    .foregroundColor(isSelected ? .white : .secondary)
                                Image(systemName: "leaf.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(isSelected ? .white : .green)
                                    .frame(width: 12)

                                VStack(alignment: .leading, spacing: 1) {
                                    HStack {
                                        Text(s.subagentSlug ?? s.projectName)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(isSelected ? .white : .primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(formatCost(s.estimatedCostUSD))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundColor(isSelected ? .white : .blue)
                                    }
                                    HStack {
                                        Text("\(formatTokens(s.tokenUsage.totalTokens)) 記號 • \(s.formattedDuration)")
                                            .font(.system(size: 9))
                                            .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                        Spacer()
                                        if s.livePID != nil {
                                            Text("🟢 Active")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.green)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 8)
                            .padding(.leading, 18)
                            .background(isSelected ? Color.purple : Color.clear)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(4)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
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

    private var timeFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Header Info
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 8) {
                            Text(session.isSubagent ? "🌿 Subagent 工作流" : "👑 主 Session")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(session.isSubagent ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundColor(session.isSubagent ? .green : .orange)
                                .cornerRadius(4)

                            Text(session.subagentSlug ?? session.parentProjectName)
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

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text(viewModel.formatCost(session.estimatedCostUSD))
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.purple)
                            Text("該 Session 耗用 \(viewModel.formatTokens(session.tokenUsage.totalTokens)) Tokens")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }

                    // Detailed Time Range & Path
                    HStack(spacing: 12) {
                        Label(session.formattedTimeRange, systemImage: "clock.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("路徑: \(session.projectPath)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(8)

                // 1. Token Velocity Sparkline & Activity Heatmap
                if !session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("📊 各對話輪次 Token 消耗 (動態範圍比例)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("藍:執行/工具 • 紫:思考規劃 • 紅:異常暴增")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("共 \(session.turns.count) 個對話輪次")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }

                        // Use a non-linear scale (square root) for better visualization of variance
                        let turnTokens = session.turns.map { Double($0.inputTokens + $0.outputTokens + $0.cacheReadTokens) }
                        let maxTurnTokens = max(1.0, turnTokens.max() ?? 1)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(Array(session.turns.enumerated()), id: \.offset) { idx, turn in
                                    let tTotal = Double(turn.inputTokens + turn.outputTokens + turn.cacheReadTokens)
                                    // Square root scaling to make smaller bars visible while keeping spikes distinct
                                    let ratio = sqrt(tTotal) / sqrt(maxTurnTokens)
                                    let isSpike = ratio > 0.85

                                    VStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(isSpike ? Color.red : (turn.taskCategory == .planning ? Color.purple : Color.blue))
                                            .frame(width: 14, height: max(4, CGFloat(ratio * 40)))

                                        Text("#\(turn.turnIndex)")
                                            .font(.system(size: 8, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                    .help("輪次 #\(turn.turnIndex)\n時間: \(timeFormatter.string(from: turn.timestamp))\n消耗: \(viewModel.formatTokens(Int64(tTotal))) Tokens\n任務: \(turn.taskDescription)")
                                }
                            }
                            .padding(8)
                        }
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(6)
                    }
                }

                // 2. Models Used
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

                // 3. Task Category Breakdown
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

                // 4. Token Granular Structure
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("🪙 該 Session 獨立 Token 結構明細")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .help("LLM API 計費方式為『每輪累加的 Context Window』。即：同一對話中，之前對話的歷史也會被送出並再次計費。這是為何 Token 數與開銷可能會非常驚人的真實原因。")
                    }

                    HStack(spacing: 8) {
                        TokenBadge(label: "輸入 (Input)", value: viewModel.formatTokens(session.tokenUsage.inputTokens), color: .blue)
                        TokenBadge(label: "生成 (Output)", value: viewModel.formatTokens(session.tokenUsage.outputTokens), color: .green)
                        TokenBadge(label: "快取命中 (Cache)", value: viewModel.formatTokens(session.tokenUsage.cacheReadTokens), color: .purple)
                        if session.tokenUsage.thinkingTokens > 0 {
                            TokenBadge(label: "思考 (Thinking)", value: viewModel.formatTokens(session.tokenUsage.thinkingTokens), color: .orange)
                        }
                    }
                }

                // 5. Chronological Turns Timeline with Timestamps
                if !session.turns.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("⏱️ 對話與任務精準時間軸 (Chronological Turns: \(session.turns.count))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)

                        LazyVStack(spacing: 6) {
                            ForEach(session.turns.prefix(25)) { turn in
                                HStack(spacing: 8) {
                                    Text("#\(turn.turnIndex)")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .leading)

                                    Text(timeFormatter.string(from: turn.timestamp))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(width: 58, alignment: .leading)

                                    Image(systemName: turn.taskCategory.iconName)
                                        .font(.system(size: 10))
                                        .foregroundColor(.purple)

                                    Text(turn.taskDescription)
                                        .font(.system(size: 11))
                                        .lineLimit(1)

                                    Spacer()

                                    if let m = turn.modelName {
                                        Text(m.replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "gemini-", with: ""))
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
        .frame(maxHeight: 520)
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
