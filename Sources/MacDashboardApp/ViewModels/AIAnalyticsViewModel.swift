import Foundation
import SwiftUI
import Combine
import MacToolKitCore

public enum CurrencyMode: String, CaseIterable, Identifiable {
    case usd = "USD ($)"
    case twd = "TWD (NT$)"

    public var id: String { rawValue }
    public var rateFromUSD: Double {
        switch self {
        case .usd: return 1.0
        case .twd: return 32.5
        }
    }
}

@MainActor
public final class AIAnalyticsViewModel: ObservableObject {
    @Published public var summary: AIAnalyticsSummary = AIAnalyticsSummary()
    @Published public var selectedSession: AISessionRecord? = nil
    @Published public var selectedCurrency: CurrencyMode = .usd
    @Published public var filterToolType: AIToolType? = nil
    @Published public var searchText: String = ""
    @Published public var isRefreshing: Bool = false
    @Published public var statusMessage: String? = nil

    private let engine = AISessionAnalyticsEngine.shared
    private let processMonitor = ProcessMonitor()
    private var refreshTask: Task<Void, Never>?

    public init() {
        refreshData()
        startAutoRefresh()
    }

    deinit {
        refreshTask?.cancel()
    }

    public func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard let self = self else { break }
                self.refreshData(silent: true)
            }
        }
    }

    public func refreshData(silent: Bool = false) {
        if !silent { isRefreshing = true }
        let eng = engine
        Task.detached(priority: .userInitiated) {
            let res = eng.fetchSummary(forceRefresh: true)
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.summary = res
                if self.selectedSession == nil {
                    self.selectedSession = res.activeSessions.first ?? res.recentSessions.first
                } else if let cur = self.selectedSession, let updated = res.recentSessions.first(where: { $0.sessionId == cur.sessionId }) {
                    self.selectedSession = updated
                }
                self.isRefreshing = false
            }
        }
    }

    public var filteredWorkspaces: [AIProjectWorkspace] {
        var list = summary.projectWorkspaces
        if let tool = filterToolType {
            list = list.compactMap { ws in
                let filteredMain = ws.mainSessions.filter { $0.toolType == tool }
                let filteredSub = ws.subagentSessions.filter { $0.toolType == tool }
                if filteredMain.isEmpty && filteredSub.isEmpty { return nil }
                return AIProjectWorkspace(
                    projectName: ws.projectName,
                    projectPath: ws.projectPath,
                    totalTokens: (filteredMain + filteredSub).reduce(0) { $0 + $1.tokenUsage.totalTokens },
                    totalCostUSD: (filteredMain + filteredSub).reduce(0.0) { $0 + $1.estimatedCostUSD },
                    totalDurationSeconds: (filteredMain + filteredSub).reduce(0.0) { $0 + $1.durationSeconds },
                    sessionCount: filteredMain.count + filteredSub.count,
                    mainSessions: filteredMain,
                    subagentSessions: filteredSub
                )
            }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter { ws in
                ws.projectName.lowercased().contains(q) ||
                ws.mainSessions.contains(where: { $0.sessionId.lowercased().contains(q) || $0.modelsUsed.contains(where: { $0.modelName.lowercased().contains(q) }) }) ||
                ws.subagentSessions.contains(where: { ($0.subagentSlug?.lowercased().contains(q) ?? false) || $0.sessionId.lowercased().contains(q) })
            }
        }
        return list
    }

    public var filteredSessions: [AISessionRecord] {
        var list = summary.recentSessions
        if let tool = filterToolType {
            list = list.filter { $0.toolType == tool }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.projectName.lowercased().contains(q) ||
                $0.parentProjectName.lowercased().contains(q) ||
                ($0.subagentSlug?.lowercased().contains(q) ?? false) ||
                $0.sessionId.lowercased().contains(q) ||
                ($0.gitBranch?.lowercased().contains(q) ?? false) ||
                $0.modelsUsed.contains(where: { $0.modelName.lowercased().contains(q) })
            }
        }
        return list
    }

    public func formatCost(_ costUSD: Double) -> String {
        switch selectedCurrency {
        case .usd:
            if costUSD < 0.01 && costUSD > 0 {
                return String(format: "$<0.01")
            }
            return String(format: "$%.2f", costUSD)
        case .twd:
            let twd = costUSD * 32.5
            if twd < 0.1 && twd > 0 {
                return "NT$<0.1"
            }
            return String(format: "NT$%.1f", twd)
        }
    }

    public func formatTokens(_ count: Int64) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2f M", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1f k", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }

    public func terminateSession(pid: pid_t) {
        let success = processMonitor.terminateProcess(pid: pid, force: true)
        if success {
            self.statusMessage = "✅ 已成功中止 AI Session 進程 (PID \(pid))"
            refreshData()
        } else {
            self.statusMessage = "❌ 無法中止進程 (PID \(pid))，可能權限不足"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.statusMessage = nil
        }
    }

    public func openWorkspace(path: String) {
        guard !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }
}
