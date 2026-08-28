import Foundation

public final class AISessionAnalyticsEngine: @unchecked Sendable {
    public static let shared = AISessionAnalyticsEngine()

    private let claudeParser = ClaudeCodeTelemetryParser.shared
    private let antigravityParser = AntigravityTelemetryParser.shared
    private let processMonitor = ProcessMonitor()
    private let lock = NSLock()

    private var cachedSummary: AIAnalyticsSummary?
    private var lastSampleTime: CFAbsoluteTime = 0

    public init() {}

    public func fetchSummary(forceRefresh: Bool = false) -> AIAnalyticsSummary {
        lock.lock()
        defer { lock.unlock() }

        let now = CFAbsoluteTimeGetCurrent()
        if !forceRefresh, let cached = cachedSummary, (now - lastSampleTime) < 3.0 {
            return cached
        }

        let claudeSessions = claudeParser.parseAllSessions(limit: 25)
        let agySessions = antigravityParser.parseAllSessions(limit: 15)

        var allSessions = claudeSessions + agySessions
        allSessions.sort { $0.lastActiveAt > $1.lastActiveAt }

        // Correlate with live processes to find active sessions
        let liveProcesses = processMonitor.sampleProcesses(limit: 80)

        var activeSessions: [AISessionRecord] = []
        var updatedSessions: [AISessionRecord] = []

        let calendar = Calendar.current
        let today = Date()

        var totalTokensToday: Int64 = 0
        var totalCostToday: Double = 0.0
        var totalTokensAllTime: Int64 = 0
        var totalCostAllTime: Double = 0.0
        var totalDurationAllTime: TimeInterval = 0

        var projectMap: [String: (count: Int, tokens: Int64, cost: Double, duration: TimeInterval)] = [:]
        var modelAggMap: [String: (turns: Int, inT: Int64, outT: Int64, cacheT: Int64, thinkT: Int64, cost: Double)] = [:]
        var taskAggMap: [AITaskCategory: (count: Int, dur: Int64, cost: Double)] = [:]

        for session in allSessions {
            var livePID: pid_t? = nil
            var liveCPU: Double? = nil
            var liveRAM: UInt64? = nil
            var liveStatus = session.status

            // Check if there is a running process belonging to this session or tool
            if session.toolType == .claudeCode {
                if let matched = liveProcesses.first(where: {
                    $0.rawName.lowercased().contains("claude") ||
                    ($0.aiContext?.toolName == "Claude Code" && $0.projectName == session.projectName)
                }) {
                    livePID = matched.pid
                    liveCPU = matched.cpuPercentage
                    liveRAM = matched.memoryBytes
                    liveStatus = matched.cpuPercentage > 15.0 ? .executingTool : (matched.cpuPercentage > 1.0 ? .thinking : .idle)
                }
            } else if session.toolType == .antigravity {
                if let matched = liveProcesses.first(where: {
                    $0.rawName.lowercased().contains("antigravity") ||
                    $0.aiContext?.toolName == "Antigravity Agent" ||
                    ($0.workingDirectory?.contains(session.sessionId) ?? false)
                }) {
                    livePID = matched.pid
                    liveCPU = matched.cpuPercentage
                    liveRAM = matched.memoryBytes
                    liveStatus = matched.cpuPercentage > 5.0 ? .active : .idle
                }
            }

            let enriched = AISessionRecord(
                sessionId: session.sessionId,
                sessionShortId: session.sessionShortId,
                toolType: session.toolType,
                projectName: session.projectName,
                projectPath: session.projectPath,
                gitBranch: session.gitBranch,
                startedAt: session.startedAt,
                lastActiveAt: session.lastActiveAt,
                durationSeconds: session.durationSeconds,
                status: livePID != nil ? liveStatus : (calendar.isDateInToday(session.lastActiveAt) ? .completed : .completed),
                livePID: livePID,
                liveCPU: liveCPU,
                liveMemoryBytes: liveRAM,
                totalTurns: session.totalTurns,
                totalToolCalls: session.totalToolCalls,
                modelsUsed: session.modelsUsed,
                taskBreakdown: session.taskBreakdown,
                tokenUsage: session.tokenUsage,
                estimatedCostUSD: session.estimatedCostUSD,
                turns: session.turns
            )

            if livePID != nil {
                activeSessions.append(enriched)
            }
            updatedSessions.append(enriched)

            // Aggregations
            totalTokensAllTime += session.tokenUsage.totalTokens
            totalCostAllTime += session.estimatedCostUSD
            totalDurationAllTime += session.durationSeconds

            if calendar.isDate(session.lastActiveAt, inSameDayAs: today) {
                totalTokensToday += session.tokenUsage.totalTokens
                totalCostToday += session.estimatedCostUSD
            }

            // Project agg
            var pData = projectMap[session.projectName] ?? (count: 0, tokens: 0, cost: 0.0, duration: 0)
            pData.count += 1
            pData.tokens += session.tokenUsage.totalTokens
            pData.cost += session.estimatedCostUSD
            pData.duration += session.durationSeconds
            projectMap[session.projectName] = pData

            // Model agg
            for m in session.modelsUsed {
                var mData = modelAggMap[m.modelName] ?? (turns: 0, inT: 0, outT: 0, cacheT: 0, thinkT: 0, cost: 0)
                mData.turns += m.turnCount
                mData.inT += m.inputTokens
                mData.outT += m.outputTokens
                mData.cacheT += m.cacheReadTokens
                mData.thinkT += m.thinkingTokens
                mData.cost += m.estimatedCostUSD
                modelAggMap[m.modelName] = mData
            }

            // Task agg
            for t in session.taskBreakdown {
                var tData = taskAggMap[t.category] ?? (count: 0, dur: 0, cost: 0)
                tData.count += t.callCount
                tData.dur += t.totalDurationMs
                tData.cost += t.estimatedCostUSD
                taskAggMap[t.category] = tData
            }
        }

        // Format project rankings
        var topProjects: [AIProjectSummary] = []
        for (pName, pStats) in projectMap {
            topProjects.append(AIProjectSummary(
                projectName: pName,
                sessionCount: pStats.count,
                totalTokens: pStats.tokens,
                totalCostUSD: pStats.cost,
                totalDurationSeconds: pStats.duration
            ))
        }
        topProjects.sort { $0.totalCostUSD > $1.totalCostUSD }

        // Format model rankings
        var allModels: [AIModelUsage] = []
        for (mName, mStats) in modelAggMap {
            allModels.append(AIModelUsage(
                modelName: mName,
                turnCount: mStats.turns,
                inputTokens: mStats.inT,
                outputTokens: mStats.outT,
                cacheReadTokens: mStats.cacheT,
                thinkingTokens: mStats.thinkT,
                estimatedCostUSD: mStats.cost
            ))
        }
        allModels.sort { $0.estimatedCostUSD > $1.estimatedCostUSD }

        // Format task breakdown
        var allTasks: [AITaskCategoryUsage] = []
        for (cat, tStats) in taskAggMap {
            allTasks.append(AITaskCategoryUsage(
                category: cat,
                callCount: tStats.count,
                totalDurationMs: tStats.dur,
                tokenShare: Double(tStats.cost) / max(0.01, totalCostAllTime),
                estimatedCostUSD: tStats.cost
            ))
        }
        allTasks.sort { $0.callCount > $1.callCount }

        let summary = AIAnalyticsSummary(
            activeSessions: activeSessions,
            recentSessions: updatedSessions,
            totalSessionsCount: updatedSessions.count,
            totalDurationSeconds: totalDurationAllTime,
            totalTokensAllTime: totalTokensAllTime,
            totalCostUSDAllTime: totalCostAllTime,
            totalTokensToday: totalTokensToday,
            totalCostUSDToday: totalCostToday,
            topProjects: topProjects,
            allModelsUsed: allModels,
            allTasksBreakdown: allTasks
        )

        self.cachedSummary = summary
        self.lastSampleTime = now
        return summary
    }
}
