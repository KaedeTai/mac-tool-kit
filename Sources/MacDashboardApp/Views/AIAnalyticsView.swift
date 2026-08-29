import SwiftUI
import MacToolKitCore

public struct AIAnalyticsView: View {
    @ObservedObject var viewModel: AIAnalyticsViewModel
    @State private var treeState = AISessionTreePresentationState(
        lifecycle: .recent,
        workspaces: []
    )

    public init(viewModel: AIAnalyticsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                provenanceBanner
                summaryStrip
                controls

                HStack(alignment: .top, spacing: 16) {
                    sessionTree
                        .frame(minWidth: 420, maxWidth: 520)
                    Divider()
                    detailPanel
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(18)
        }
        .onAppear {
            treeState.reset(
                lifecycle: viewModel.selectedLifecycle,
                workspaces: viewModel.filteredWorkspaces
            )
            revealSelectedRecentSession()
        }
        .onChange(of: viewModel.selectedLifecycle) { _, lifecycle in
            viewModel.reconcileSelectionToScope()
            viewModel.startAutoRefresh()
            treeState.reset(
                lifecycle: lifecycle,
                workspaces: viewModel.filteredWorkspaces
            )
            revealSelectedRecentSession()
        }
        .onChange(of: viewModel.filterToolType) { _, _ in
            viewModel.reconcileSelectionToScope()
            treeState.reconcile(
                lifecycle: viewModel.selectedLifecycle,
                workspaces: viewModel.filteredWorkspaces
            )
            revealSelectedRecentSession()
        }
        .onChange(of: viewModel.searchText) { _, query in
            viewModel.reconcileSelectionToScope()
            if query.isEmpty {
                treeState.reset(
                    lifecycle: viewModel.selectedLifecycle,
                    workspaces: viewModel.filteredWorkspaces
                )
                revealSelectedRecentSession()
            } else {
                treeState.expandSearchResults(in: viewModel.filteredWorkspaces)
            }
        }
        .onChange(of: viewModel.showActivityOnlyRecords) { _, _ in
            viewModel.reconcileSelectionToScope()
            treeState.reconcile(
                lifecycle: viewModel.selectedLifecycle,
                workspaces: viewModel.filteredWorkspaces
            )
            revealSelectedRecentSession()
        }
        .onChange(of: viewModel.refreshGeneration) { _, _ in
            treeState.reconcile(
                lifecycle: viewModel.selectedLifecycle,
                workspaces: viewModel.filteredWorkspaces
            )
        }
        .onChange(of: viewModel.selectedSession?.id) { _, _ in
            revealSelectedRecentSession()
        }
    }

    private var provenanceBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundColor(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("事實模式")
                    .font(.system(size: 13, weight: .bold))
                Text("Session 狀態優先使用 Codex 本機 turn state；其餘工具以 Mac 程序、專案路徑與近期 transcript 活動交叉判定。費用只顯示逐模型 token 套用官方標準費率的 API 等價估算，不宣稱訂閱或信用額度扣款。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("來源：本機 provider logs + Dashboard 歷史索引")
                Text("History：\(viewModel.summary.historyPersistenceStatus.label)")
                    .help(viewModel.summary.historyPersistenceStatus.detail)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(viewModel.summary.historyPersistenceStatus.label == "不可取得" ? .orange : .secondary)
        }
        .padding(12)
        .background(Color.green.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.green.opacity(0.25)))
        .cornerRadius(8)
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            summaryValue("執行中", "\(viewModel.summary.activeSessions.count)", "本機 turn state 或程序＋近期活動")
            Divider().frame(height: 48)
            summaryValue("Recent 24h", "\(viewModel.summary.recentSessions.count)", "程序閒置或目前未執行")
            Divider().frame(height: 48)
            summaryValue("永久 History", "\(viewModel.summary.historySessions.count)", "不受 parser 數量上限淘汰")
            Divider().frame(height: 48)
            summaryValue("Provider 回報 tokens", viewModel.formatTokens(viewModel.summary.totalTokensAllTime), "缺少 token 欄位的歷史不以 0 冒充完整量")
        }
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        .cornerRadius(8)
    }

    private func summaryValue(_ title: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 10)).foregroundColor(.secondary)
            Text(value).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(note).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("範圍", selection: $viewModel.selectedLifecycle) {
                    Text("Active").tag(AISessionLifecycle.active)
                    Text("Recent 24h").tag(AISessionLifecycle.recent)
                    Text("History").tag(AISessionLifecycle.history)
                }
                .pickerStyle(.segmented)
                .frame(width: 310)

                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("搜尋專案路徑、session 名稱或 ID", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                }
                .padding(7)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }

            HStack(spacing: 10) {
                Picker("工具", selection: $viewModel.filterToolType) {
                    Text("全部工具").tag(AIToolType?.none)
                    ForEach(AIToolType.allCases) { Text($0.rawValue).tag(AIToolType?.some($0)) }
                }
                .frame(width: 190)

                Toggle("顯示 API 等價估算（非帳單）", isOn: $viewModel.showAPIEstimates)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .help("以本機費率表比較 API 用量；不是訂閱帳單或 credits 扣款")

                if viewModel.selectedLifecycle != .active {
                    Toggle(
                        "顯示僅活動紀錄（\(viewModel.activityOnlyRecordCount)）",
                        isOn: $viewModel.showActivityOnlyRecords
                    )
                    .toggleStyle(.checkbox)
                    .font(.system(size: 10))
                    .help("這些紀錄有真實 session ID 與時間戳，但沒有模型或 token 證據；預設不混入用量分析")
                }

                Spacer()

                Button { viewModel.refreshData() } label: {
                    Label("重新整理", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }

            if viewModel.selectedLifecycle == .history {
                Text("History 不做背景重掃；保留資料只在你按「重新整理」時同步，避免數千筆歷史持續重建畫面。")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var sessionTree: some View {
        let workspaces = viewModel.filteredWorkspaces
        let sessionCount = viewModel.scopedSessions.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("專案 → 主 Session → 子 Session")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Text("\(sessionCount) sessions")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if workspaces.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: viewModel.selectedLifecycle == .active ? "pause.circle" : "tray")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary)
                    Text(viewModel.selectedLifecycle == .active ? "目前沒有偵測到執行中的 session" : "此範圍沒有符合條件的 session")
                        .font(.system(size: 12, weight: .medium))
                    Text("Codex 採本機 turn state；Claude／Antigravity 採程序、工作目錄與 transcript 活動交叉判定。")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(workspaces) { workspace in
                        workspaceSection(workspace)
                    }
                }
            }
        }
    }

    private func workspaceSection(_ workspace: AIProjectWorkspace) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            workspaceHeader(workspace)

            if treeState.isWorkspaceExpanded(workspace) {
                ForEach(treeState.visibleMainSessions(in: workspace)) { main in
                    mainSessionBlock(main, workspace: workspace)
                }

                let remainingMains = treeState.remainingMainSessionCount(in: workspace)
                if remainingMains > 0 {
                    loadMoreButton("再顯示最多 \(min(treeState.batchSize, remainingMains)) 個主 Session（尚有 \(remainingMains)）") {
                        treeState.loadMoreMainSessions(in: workspace)
                    }
                }

                unlinkedSessionSection(workspace)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15)))
        .cornerRadius(8)
    }

    private func workspaceHeader(_ workspace: AIProjectWorkspace) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                treeState.toggleWorkspace(workspace)
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: treeState.isWorkspaceExpanded(workspace) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 12, height: 18)
                    Image(systemName: "folder.fill").foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(workspaceDisplayName(workspace)).font(.system(size: 12, weight: .bold))
                            Text(workspaceHierarchyCount(workspace))
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text(workspacePathLabel(workspace))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if workspaceHasTokenEvidence(workspace) {
                            Text("\(viewModel.formatTokens(workspace.totalTokens)) tokens")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        if let cost = workspaceCost(workspace) {
                            Text(cost)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !workspace.projectPath.isEmpty {
                Button {
                    viewModel.openWorkspace(path: workspace.projectPath)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("在 Finder 開啟專案資料夾")
            }
        }
    }

    @ViewBuilder
    private func mainSessionBlock(_ main: AISessionRecord, workspace: AIProjectWorkspace) -> some View {
        let childCount = workspace.children(of: main).count
        HStack(spacing: 0) {
            if childCount > 0 {
                Button {
                    treeState.toggleSession(main)
                } label: {
                    Image(systemName: treeState.isSessionExpanded(main) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 28)
                }
                .buttonStyle(.plain)
                .help(treeState.isSessionExpanded(main) ? "收合子 Session" : "展開 \(childCount) 個子 Session")
            } else {
                Color.clear.frame(width: 20, height: 1)
            }
            sessionRow(
                main,
                indent: 0,
                relation: mainRelationLabel(workspace: workspace, childCount: childCount)
            )
        }

        ForEach(treeState.visibleChildren(of: main, in: workspace)) { child in
            sessionRow(child, indent: 24, relation: "↳ 子 Session")
        }

        let remainingChildren = treeState.remainingChildCount(of: main, in: workspace)
        if remainingChildren > 0 {
            loadMoreButton("再顯示最多 \(min(treeState.batchSize, remainingChildren)) 個子 Session（尚有 \(remainingChildren)）") {
                treeState.loadMoreChildren(of: main, in: workspace)
            }
            .padding(.leading, 24)
        }
    }

    @ViewBuilder
    private func unlinkedSessionSection(_ workspace: AIProjectWorkspace) -> some View {
        if !workspace.unlinkedSubagentSessions.isEmpty {
            Button {
                treeState.toggleUnlinkedSection(in: workspace)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: treeState.isUnlinkedSectionExpanded(in: workspace) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 12)
                    Image(systemName: "link.badge.plus").foregroundColor(.orange)
                    Text("找不到父 Session 的子 Session（\(workspace.unlinkedSubagentSessions.count)）")
                        .font(.system(size: 9, weight: .semibold))
                    Text("provider 有子代理 ID，但父 Session 紀錄不在本機索引")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 3)

            ForEach(treeState.visibleUnlinkedSessions(in: workspace)) { child in
                sessionRow(child, indent: 24, relation: "未連結")
            }

            let remainingUnlinked = treeState.remainingUnlinkedSessionCount(in: workspace)
            if remainingUnlinked > 0 {
                loadMoreButton("再顯示最多 \(min(treeState.batchSize, remainingUnlinked)) 個未連結 Session（尚有 \(remainingUnlinked)）") {
                    treeState.loadMoreUnlinkedSessions(in: workspace)
                }
            }
        }
    }

    private func loadMoreButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: "ellipsis.circle")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }

    private func sessionRow(_ session: AISessionRecord, indent: CGFloat, relation: String) -> some View {
        let selected = viewModel.selectedSession?.id == session.id
        return Button {
            viewModel.selectedSession = session
        } label: {
            HStack(spacing: 8) {
                Image(systemName: session.toolType.iconName)
                    .foregroundColor(selected ? .white : .purple)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(relation).font(.system(size: 9, weight: .bold))
                        Text(session.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        if session.lifecycle != viewModel.selectedLifecycle {
                            Text("跨分頁父 Session")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .background(Color.blue.opacity(0.15))
                                .cornerRadius(3)
                        }
                    }
                    HStack(spacing: 7) {
                        statusPill(session)
                        Text("#\(session.sessionShortId)")
                        Text(sessionTokenLabel(session))
                    }
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(selected ? .white.opacity(0.82) : .secondary)
                }
                Spacer()
                if AISessionCostPresentation.shouldDisplay(
                    session.cost,
                    estimatesEnabled: viewModel.showAPIEstimates
                ), let amount = session.cost.amountUSD {
                    Text("API 估算 \(viewModel.formatCost(amount))")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(selected ? .white : costColor(session.cost))
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .padding(.leading, indent)
            .background(selected ? Color.purple : Color.clear)
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func revealSelectedRecentSession() {
        guard viewModel.selectedLifecycle == .recent,
              let selected = viewModel.selectedSession else { return }
        treeState.reveal(selected, in: viewModel.filteredWorkspaces)
    }

    private func workspaceDisplayName(_ workspace: AIProjectWorkspace) -> String {
        if isClaudeInternalRuntime(workspace) { return "Claude 內部背景工作" }
        if workspace.projectPath.isEmpty && workspace.projectName == "Unlinked Claude Metadata" {
            return "無法歸屬專案的 Claude Metadata"
        }
        return workspace.projectName
    }

    private func workspaceHierarchyCount(_ workspace: AIProjectWorkspace) -> String {
        if isClaudeInternalRuntime(workspace) {
            return "\(workspace.mainSessions.count) 個獨立 Runtime"
        }
        return "\(workspace.mainSessions.count) 主 · \(workspace.subagentSessions.count) 子"
    }

    private func workspacePathLabel(_ workspace: AIProjectWorkspace) -> String {
        if isClaudeInternalRuntime(workspace) {
            return "Claude ~/.claude 內部工作；不歸屬使用者專案"
        }
        if workspace.projectPath.isEmpty && workspace.projectName == "Unlinked Claude Metadata" {
            return "provider 紀錄沒有可驗證的工作目錄（cwd）"
        }
        return workspace.projectPath.isEmpty ? "未連結專案路徑" : workspace.projectPath
    }

    private func mainRelationLabel(workspace: AIProjectWorkspace, childCount: Int) -> String {
        if isClaudeInternalRuntime(workspace) { return "獨立 Runtime" }
        return childCount > 0 ? "主 Session · \(childCount) 子" : "主 Session · 無子 Session"
    }

    private func isClaudeInternalRuntime(_ workspace: AIProjectWorkspace) -> Bool {
        workspace.projectPath.isEmpty && workspace.projectName == "Unlinked Claude Runtime"
    }

    private func statusPill(_ session: AISessionRecord) -> some View {
        Text(session.status.rawValue)
            .font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(statusColor(session.status).opacity(0.16))
            .foregroundColor(statusColor(session.status))
            .cornerRadius(3)
            .help("\(session.statusSource.label)：\(session.statusSource.detail)")
    }

    private func sessionTokenLabel(_ session: AISessionRecord) -> String {
        if case .unavailable = session.tokenUsage.source {
            return session.isActivityOnlyRecord ? "僅活動紀錄" : "模型紀錄"
        }
        return "\(viewModel.formatTokens(session.tokenUsage.totalTokens)) tokens"
    }

    @ViewBuilder
    private var detailPanel: some View {
        if let session = viewModel.selectedSession {
            SessionEvidenceView(session: session, viewModel: viewModel)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "sidebar.left").font(.system(size: 30)).foregroundColor(.secondary)
                Text("選擇一個 session 查看來源與計算方式").foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }

    private func workspaceCost(_ workspace: AIProjectWorkspace) -> String? {
        if viewModel.showAPIEstimates, let estimate = workspace.apiEquivalentEstimateUSD {
            let prefix = workspace.apiEquivalentEstimateIsComplete ? "API 等價估算" : "部分 API 估算"
            return "\(prefix) \(viewModel.formatCost(estimate))"
        }
        if workspace.apiEquivalentEstimateUSD != nil { return "API 估算已隱藏" }
        return nil
    }

    private func workspaceHasTokenEvidence(_ workspace: AIProjectWorkspace) -> Bool {
        (workspace.mainSessions + workspace.subagentSessions).contains { session in
            if case .unavailable = session.tokenUsage.source { return false }
            return true
        }
    }

    private func statusColor(_ status: AISessionStatus) -> Color {
        switch status {
        case .unknown: return .orange
        case .active, .executingTool: return .blue
        case .thinking: return .purple
        case .idle: return .green
        case .completed: return .secondary
        case .aborted: return .red
        }
    }

    private func costColor(_ cost: AICostValue) -> Color {
        switch cost.kind {
        case .actualBilling: return .secondary
        case .apiEquivalentEstimate: return .purple
        case .unavailable: return .secondary
        }
    }
}

private struct SessionEvidenceView: View {
    let session: AISessionRecord
    @ObservedObject var viewModel: AIAnalyticsViewModel

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private var projectLocationLabel: String {
        if session.projectPath.isEmpty && session.projectName == "Unlinked Claude Runtime" {
            return "Claude ~/.claude 內部工作；不歸屬使用者專案"
        }
        if session.projectPath.isEmpty && session.projectName == "Unlinked Claude Metadata" {
            return "provider 紀錄沒有可驗證的工作目錄（cwd）"
        }
        return session.projectPath.isEmpty ? "未連結專案路徑" : session.projectPath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(session.title).font(.system(size: 17, weight: .bold))
                Text("\(session.toolType.rawValue) · #\(session.sessionShortId)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                Text(projectLocationLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Divider()
            evidenceRow("執行狀態", session.status.rawValue, session.statusSource)
            if session.isActivityOnlyRecord {
                Label(
                    "僅活動紀錄：session ID、路徑與時間戳有來源證據，但 provider 沒留下模型或 token 欄位；保留於歷史索引，不納入用量與費用分析。",
                    systemImage: "clock.badge.questionmark"
                )
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(6)
            } else {
                if !session.modelsUsed.isEmpty {
                    evidenceRow(
                        "模型",
                        session.modelsUsed.map(\.modelName).joined(separator: ", "),
                        .providerReported("Model identifiers present in provider messages or turn context")
                    )
                }
                if hasTokenEvidence {
                    evidenceRow("Token", tokenValue, session.tokenUsage.source)
                }
            }
            if AISessionCostPresentation.shouldDisplay(
                session.cost,
                estimatesEnabled: viewModel.showAPIEstimates
            ), let amount = session.cost.amountUSD {
                evidenceRow("API 等價估算", viewModel.formatCost(amount), session.cost.source)
            }
            evidenceRow("最後活動", Self.dateFormatter.string(from: session.lastActiveAt), .providerReported("Latest timestamp present in provider log"))
            evidenceRow("Transcript 範圍", transcriptSpan, .derived("First and last provider-log timestamps; not continuous running time"))

            if hasTokenEvidence {
                Divider()
                Text("Token 結構").font(.system(size: 12, weight: .bold))
                HStack(spacing: 8) {
                    tokenCell("Input", session.tokenUsage.inputTokens)
                    tokenCell("Output", session.tokenUsage.outputTokens)
                    tokenCell("Cache read", session.tokenUsage.cacheReadTokens)
                    tokenCell("Cache write", session.tokenUsage.cacheWriteTokens)
                    tokenCell("Reasoning subset", session.tokenUsage.thinkingTokens)
                }
                Text("總 token 採 provider total；cache 與 reasoning 可能是 input/output 的子集合，不重複相加。")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }

            if session.isSubagent {
                Divider()
                Text("父子關係").font(.system(size: 12, weight: .bold))
                Text(session.parentSessionId.map { "父 Session：#\(String($0.prefix(8)))（provider ID）" }
                     ?? "未連結：provider 未提供父 Session ID")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(session.parentSessionId == nil ? .orange : .secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        .cornerRadius(8)
    }

    private var tokenValue: String {
        return "\(viewModel.formatTokens(session.tokenUsage.totalTokens)) tokens"
    }

    private var hasTokenEvidence: Bool {
        if case .unavailable = session.tokenUsage.source { return false }
        return true
    }

    private var transcriptSpan: String {
        let seconds = Int(session.transcriptSpanSeconds)
        if seconds < 60 { return "\(seconds) 秒" }
        if seconds < 3600 { return "\(seconds / 60) 分鐘" }
        return "\(seconds / 3600) 小時 \((seconds % 3600) / 60) 分（非 running 時長）"
    }

    private func evidenceRow(_ label: String, _ value: String, _ source: AIDataProvenance) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label).font(.system(size: 10, weight: .semibold)).frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.system(size: 12, weight: .medium))
                Text("\(source.label) · \(source.detail)")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private func tokenCell(_ label: String, _ value: Int64) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 8)).foregroundColor(.secondary)
            Text(viewModel.formatTokens(value)).font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(7)
        .background(Color.purple.opacity(0.07))
        .cornerRadius(5)
    }
}
