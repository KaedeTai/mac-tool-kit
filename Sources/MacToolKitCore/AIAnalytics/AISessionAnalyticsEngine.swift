import Foundation

public final class AISessionAnalyticsEngine: @unchecked Sendable {
    public static let shared = AISessionAnalyticsEngine()

    private let claudeParser: ClaudeCodeTelemetryParser
    private let antigravityParser: AntigravityTelemetryParser
    private let codexParser: CodexTelemetryParser
    private let historyStore: AISessionHistoryStore
    private let codexRuntimeProbe: CodexRuntimeStatusProbe
    private let processMonitor: ProcessMonitor
    private let lock = NSLock()
    private var cachedSummary: AIAnalyticsSummary?
    private var lastSampleTime: CFAbsoluteTime = 0

    public init(
        claudeParser: ClaudeCodeTelemetryParser = .shared,
        antigravityParser: AntigravityTelemetryParser = .shared,
        codexParser: CodexTelemetryParser = .shared,
        historyStore: AISessionHistoryStore = AISessionHistoryStore(),
        codexRuntimeProbe: CodexRuntimeStatusProbe = CodexRuntimeStatusProbe(),
        processMonitor: ProcessMonitor = ProcessMonitor()
    ) {
        self.claudeParser = claudeParser
        self.antigravityParser = antigravityParser
        self.codexParser = codexParser
        self.historyStore = historyStore
        self.codexRuntimeProbe = codexRuntimeProbe
        self.processMonitor = processMonitor
    }

    public func fetchSummary(forceRefresh: Bool = false) -> AIAnalyticsSummary {
        lock.lock()
        defer { lock.unlock() }

        let sampleTime = CFAbsoluteTimeGetCurrent()
        if !forceRefresh, let cachedSummary, sampleTime - lastSampleTime < 10 {
            return cachedSummary
        }

        let providerRecords = claudeParser.parseAllSessions()
            + antigravityParser.parseAllSessions(limit: nil)
            + codexParser.parseAllSessions()
        let mergedSessions = historyStore.merge(current: providerRecords)
        let processEvidence = AISessionRuntimeReconciler.processEvidence(
            from: processMonitor.sampleProcesses(limit: nil)
        )
        let allSessions = AISessionRuntimeReconciler.reconcile(
            records: mergedSessions,
            codexStates: codexRuntimeProbe.latestThreadStates(),
            codexExecutionCWDs: codexRuntimeProbe.latestExecutionWorkingDirectories(),
            processes: processEvidence,
            now: Date()
        )
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
        let summary = Self.buildSummary(
            sessions: allSessions,
            now: Date(),
            historyPersistenceStatus: historyStore.persistenceStatus()
        )
        cachedSummary = summary
        lastSampleTime = sampleTime
        return summary
    }

    public static func buildSummary(
        sessions: [AISessionRecord],
        now: Date,
        historyPersistenceStatus: AIDataProvenance = .unavailable("History persistence not evaluated in this summary")
    ) -> AIAnalyticsSummary {
        let active = sessions.filter {
            AISessionLifecycle.classify(status: $0.status, lastActiveAt: $0.lastActiveAt, now: now) == .active
        }
        let recent = sessions.filter {
            AISessionLifecycle.classify(status: $0.status, lastActiveAt: $0.lastActiveAt, now: now) == .recent
        }
        let history = sessions.filter {
            AISessionLifecycle.classify(status: $0.status, lastActiveAt: $0.lastActiveAt, now: now) == .history
        }

        let workspaceGroups = Dictionary(grouping: sessions) { session in
            session.projectPath.isEmpty ? "unlinked:\(session.parentProjectName)" : session.projectPath
        }
        let workspaces = workspaceGroups.map { path, projectSessions -> AIProjectWorkspace in
            let mains = projectSessions.filter { !$0.isSubagent }.sorted { $0.lastActiveAt > $1.lastActiveAt }
            let children = projectSessions.filter(\.isSubagent).sorted { $0.lastActiveAt > $1.lastActiveAt }
            let estimateValues = projectSessions.compactMap { session in
                session.cost.kind == .apiEquivalentEstimate ? session.cost.amountUSD : nil
            }
            let tokenBearingSessions = projectSessions.filter { session in
                guard session.tokenUsage.totalTokens > 0 else { return false }
                if case .unavailable = session.tokenUsage.source { return false }
                return true
            }
            return AIProjectWorkspace(
                projectName: projectSessions.first?.parentProjectName ?? "Unlinked",
                projectPath: path.hasPrefix("unlinked:") ? "" : path,
                totalTokens: projectSessions.reduce(0) { $0 + $1.tokenUsage.totalTokens },
                actualCostUSD: nil,
                apiEquivalentEstimateUSD: estimateValues.isEmpty ? nil : estimateValues.reduce(0, +),
                apiEquivalentEstimateIsComplete: !tokenBearingSessions.isEmpty
                    && tokenBearingSessions.allSatisfy {
                        $0.cost.kind == .apiEquivalentEstimate && $0.cost.amountUSD != nil
                    },
                totalDurationSeconds: projectSessions.reduce(0) { $0 + $1.durationSeconds },
                sessionCount: projectSessions.count,
                mainSessions: mains,
                subagentSessions: children
            )
        }.sorted {
            let lhs = $0.mainSessions.map(\.lastActiveAt).max() ?? $0.subagentSessions.map(\.lastActiveAt).max() ?? .distantPast
            let rhs = $1.mainSessions.map(\.lastActiveAt).max() ?? $1.subagentSessions.map(\.lastActiveAt).max() ?? .distantPast
            return lhs > rhs
        }

        let projects = workspaces.map { workspace in
            AIProjectSummary(
                projectName: workspace.projectName,
                sessionCount: workspace.sessionCount,
                totalTokens: workspace.totalTokens,
                actualCostUSD: workspace.actualCostUSD,
                apiEquivalentEstimateUSD: workspace.apiEquivalentEstimateUSD,
                totalDurationSeconds: workspace.totalDurationSeconds
            )
        }.sorted { $0.totalTokens > $1.totalTokens }

        var modelMap: [String: (turns: Int, input: Int64, output: Int64, cache: Int64, thinking: Int64, estimate: Double)] = [:]
        var taskMap: [AITaskCategory: (count: Int, duration: Int64, estimate: Double)] = [:]
        for session in sessions {
            for model in session.modelsUsed {
                var value = modelMap[model.modelName] ?? (0, 0, 0, 0, 0, 0)
                value.turns += model.turnCount
                value.input += model.inputTokens
                value.output += model.outputTokens
                value.cache += model.cacheReadTokens
                value.thinking += model.thinkingTokens
                value.estimate += model.estimatedCostUSD
                modelMap[model.modelName] = value
            }
            for task in session.taskBreakdown {
                var value = taskMap[task.category] ?? (0, 0, 0)
                value.count += task.callCount
                value.duration += task.totalDurationMs
                value.estimate += task.estimatedCostUSD
                taskMap[task.category] = value
            }
        }

        let models = modelMap.map { name, value in
            AIModelUsage(
                modelName: name,
                turnCount: value.turns,
                inputTokens: value.input,
                outputTokens: value.output,
                cacheReadTokens: value.cache,
                thinkingTokens: value.thinking,
                estimatedCostUSD: value.estimate
            )
        }.sorted { $0.inputTokens + $0.outputTokens > $1.inputTokens + $1.outputTokens }

        let estimateTotal = max(0.000_001, sessions.compactMap {
            $0.cost.kind == .apiEquivalentEstimate ? $0.cost.amountUSD : nil
        }.reduce(0, +))
        let tasks = taskMap.map { category, value in
            AITaskCategoryUsage(
                category: category,
                callCount: value.count,
                totalDurationMs: value.duration,
                tokenShare: value.estimate / estimateTotal,
                estimatedCostUSD: value.estimate
            )
        }.sorted { $0.callCount > $1.callCount }

        return AIAnalyticsSummary(
            activeSessions: active,
            projectWorkspaces: workspaces,
            recentSessions: recent,
            historySessions: history,
            totalSessionsCount: sessions.count,
            totalDurationSeconds: sessions.reduce(0) { $0 + $1.durationSeconds },
            totalTokensAllTime: sessions.reduce(0) { $0 + $1.tokenUsage.totalTokens },
            totalCostUSDAllTime: 0,
            totalTokensToday: 0,
            totalCostUSDToday: 0,
            topProjects: projects,
            allModelsUsed: models,
            allTasksBreakdown: tasks,
            historyPersistenceStatus: historyPersistenceStatus
        )
    }
}
