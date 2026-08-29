import Foundation
import SwiftUI
import Combine
import MacToolKitCore

@MainActor
public final class AIAnalyticsViewModel: ObservableObject {
    @Published public var summary = AIAnalyticsSummary()
    @Published public var selectedSession: AISessionRecord?
    @Published public var filterToolType: AIToolType?
    @Published public var searchText = ""
    @Published public var selectedLifecycle: AISessionLifecycle = .recent
    @Published public var showAPIEstimates = true
    @Published public var showActivityOnlyRecords = false
    @Published public var isRefreshing = false
    @Published public private(set) var refreshGeneration = 0

    private let engine = AISessionAnalyticsEngine.shared
    private var refreshTask: Task<Void, Never>?

    public init() {
        refreshData()
        startAutoRefresh()
    }

    deinit { refreshTask?.cancel() }

    public func startAutoRefresh() {
        refreshTask?.cancel()
        guard let interval = AISessionRefreshPolicy.interval(for: selectedLifecycle) else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else { break }
                self.refreshData(silent: true)
            }
        }
    }

    public func refreshData(silent: Bool = false) {
        if !silent { isRefreshing = true }
        let engine = engine
        Task.detached(priority: .userInitiated) {
            let result = engine.fetchSummary(forceRefresh: true)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.summary = result
                self.refreshGeneration += 1
                self.reconcileSelectionToScope()
                self.isRefreshing = false
            }
        }
    }

    public var scopedSessions: [AISessionRecord] {
        filteredLifecycleSessions.filter {
            AISessionPresentation.shouldInclude(
                $0,
                lifecycle: selectedLifecycle,
                showActivityOnlyRecords: showActivityOnlyRecords
            )
        }
    }

    public var activityOnlyRecordCount: Int {
        guard selectedLifecycle != .active else { return 0 }
        return filteredLifecycleSessions.filter(\.isActivityOnlyRecord).count
    }

    private var filteredLifecycleSessions: [AISessionRecord] {
        let source: [AISessionRecord]
        switch selectedLifecycle {
        case .active: source = summary.activeSessions
        case .recent: source = summary.recentSessions
        case .history: source = summary.historySessions
        }
        return source.filter { session in
            if let filterToolType, session.toolType != filterToolType { return false }
            guard !searchText.isEmpty else { return true }
            let query = searchText.lowercased()
            return session.title.lowercased().contains(query)
                || session.parentProjectName.lowercased().contains(query)
                || session.projectPath.lowercased().contains(query)
                || session.sessionId.lowercased().contains(query)
                || (session.subagentSlug?.lowercased().contains(query) ?? false)
        }
    }

    public var filteredWorkspaces: [AIProjectWorkspace] {
        let allowed = Set(scopedSessions.map(\.id))
        return summary.projectWorkspaces.compactMap { workspace in
            let children = workspace.subagentSessions.filter { allowed.contains($0.id) }
            let parentIDsNeededForContext = Set(children.compactMap { child in
                child.parentSessionId.map { "\(child.toolType.rawValue)::\($0)" }
            })
            let mains = workspace.mainSessions.filter {
                allowed.contains($0.id)
                    || parentIDsNeededForContext.contains("\($0.toolType.rawValue)::\($0.sessionId)")
            }
            let scopedMains = mains.filter { allowed.contains($0.id) }
            let sessions = scopedMains + children
            guard !sessions.isEmpty else { return nil }
            let estimates = sessions.compactMap { $0.cost.kind == .apiEquivalentEstimate ? $0.cost.amountUSD : nil }
            let tokenBearingSessions = sessions.filter { session in
                guard session.tokenUsage.totalTokens > 0 else { return false }
                if case .unavailable = session.tokenUsage.source { return false }
                return true
            }
            return AIProjectWorkspace(
                projectName: workspace.projectName,
                projectPath: workspace.projectPath,
                totalTokens: sessions.reduce(0) { $0 + $1.tokenUsage.totalTokens },
                actualCostUSD: nil,
                apiEquivalentEstimateUSD: estimates.isEmpty ? nil : estimates.reduce(0, +),
                apiEquivalentEstimateIsComplete: !tokenBearingSessions.isEmpty
                    && tokenBearingSessions.allSatisfy {
                        $0.cost.kind == .apiEquivalentEstimate && $0.cost.amountUSD != nil
                    },
                totalDurationSeconds: sessions.reduce(0) { $0 + $1.durationSeconds },
                sessionCount: sessions.count,
                mainSessions: mains,
                subagentSessions: children
            )
        }
    }

    public func reconcileSelectionToScope() {
        selectedSession = AISessionScopeSelection.reconcile(
            current: selectedSession,
            visibleSessions: scopedSessions
        )
    }

    public func formatCost(_ amountUSD: Double) -> String {
        if amountUSD >= 1 { return String(format: "$%.2f USD", amountUSD) }
        if amountUSD >= 0.01 { return String(format: "$%.4f USD", amountUSD) }
        return String(format: "$%.6f USD", amountUSD)
    }

    public func formatCost(_ cost: AICostValue) -> String {
        guard let amount = cost.amountUSD else { return "API 估算不可計算" }
        if cost.kind == .apiEquivalentEstimate && !showAPIEstimates {
            return "API 估算已隱藏"
        }
        guard cost.kind == .apiEquivalentEstimate else { return "API 估算不可計算" }
        return "API 等價估算 " + formatCost(amount)
    }

    public func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000 { return String(format: "%.2f M", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1f k", Double(count) / 1_000) }
        return "\(count)"
    }

    public func openWorkspace(path: String) {
        guard !path.isEmpty else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}
