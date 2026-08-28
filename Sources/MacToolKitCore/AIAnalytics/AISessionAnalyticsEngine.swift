import Foundation

public final class AISessionAnalyticsEngine: @unchecked Sendable {
    public static let shared = AISessionAnalyticsEngine()

    private let claudeParser = ClaudeCodeTelemetryParser.shared
    private let antigravityParser = AntigravityTelemetryParser.shared
    private let codexParser = CodexTelemetryParser.shared
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
        let codexSessions = codexParser.parseAllSessions(limit: 15)

        var allSessions = claudeSessions + agySessions + codexSessions
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
        var matchedPIDs = Set<pid_t>()

        for session in allSessions {
            var livePID: pid_t? = nil
            var liveCPU: Double? = nil
            var liveRAM: UInt64? = nil
            var liveStatus = session.status

            // Accurate correlation: Match running process whose working directory is precisely the session path
            if session.toolType == .claudeCode {
                if let matched = liveProcesses.first(where: { p in
                    guard !matchedPIDs.contains(p.pid) else { return false }
                    guard p.rawName.lowercased().contains("claude") || (p.commandLine?.contains("claude") ?? false) else { return false }
                    guard let pCwd = p.workingDirectory, !pCwd.isEmpty, pCwd != "/", pCwd != NSHomeDirectory() else { return false }
                    guard pCwd == session.projectPath || pCwd.hasPrefix(session.projectPath + "/") || session.projectPath.hasPrefix(pCwd + "/") else { return false }
                    // Must be active recently or process actively running in that directory
                    return true
                }) {
                    matchedPIDs.insert(matched.pid)
                    livePID = matched.pid
                    liveCPU = matched.cpuPercentage
                    liveRAM = matched.memoryBytes
                    liveStatus = matched.cpuPercentage > 15.0 ? .executingTool : (matched.cpuPercentage > 1.0 ? .thinking : .idle)
                }
            } else if session.toolType == .antigravity {
                // Antigravity language_server runs from `/`, so we cannot rely on CWD.
                // We match if the session is very recent (active in last 5 mins) OR if we find an active antigravity process
                let isRecent = Date().timeIntervalSince(session.lastActiveAt) < 300
                if let matched = liveProcesses.first(where: { p in
                    guard !matchedPIDs.contains(p.pid) else { return false }
                    let cmd = (p.commandLine ?? "").lowercased()
                    let name = p.rawName.lowercased()
                    return name.contains("antigravity") || cmd.contains("antigravity") || cmd.contains("language_server")
                }) {
                    if isRecent {
                        matchedPIDs.insert(matched.pid)
                        livePID = matched.pid
                        liveCPU = matched.cpuPercentage
                        liveRAM = matched.memoryBytes
                        liveStatus = matched.cpuPercentage > 1.0 ? .thinking : .idle
                    }
                } else if isRecent {
                    // Fallback: If modified in last 5 mins, consider it active even if process matching failed
                    liveStatus = .idle
                }
            } else if session.toolType == .codex {
                // Codex app-server runs globally
                let isRecent = Date().timeIntervalSince(session.lastActiveAt) < 300
                if isRecent {
                    if let matched = liveProcesses.first(where: { p in
                        guard !matchedPIDs.contains(p.pid) else { return false }
                        let cmd = (p.commandLine ?? "").lowercased()
                        let name = p.rawName.lowercased()
                        return name.contains("codex") || cmd.contains("codex")
                    }) {
                        matchedPIDs.insert(matched.pid)
                        livePID = matched.pid
                        liveCPU = matched.cpuPercentage
                        liveRAM = matched.memoryBytes
                        liveStatus = matched.cpuPercentage > 1.0 ? .thinking : .idle
                    } else {
                        liveStatus = .idle
                    }
                }
            }

            let enriched = AISessionRecord(
                sessionId: session.sessionId,
                sessionShortId: session.sessionShortId,
                toolType: session.toolType,
                projectName: session.projectName,
                parentProjectName: session.parentProjectName,
                projectPath: session.projectPath,
                gitBranch: session.gitBranch,
                isSubagent: session.isSubagent,
                subagentSlug: session.subagentSlug,
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
            var pData = projectMap[session.parentProjectName] ?? (count: 0, tokens: 0, cost: 0.0, duration: 0)
            pData.count += 1
            pData.tokens += session.tokenUsage.totalTokens
            pData.cost += session.estimatedCostUSD
            pData.duration += session.durationSeconds
            projectMap[session.parentProjectName] = pData

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

        // Build Hierarchical Project Workspaces Group
        var workspaceDict: [String: (path: String, main: [AISessionRecord], sub: [AISessionRecord])] = [:]
        for session in updatedSessions {
            let pKey = session.parentProjectName
            var existing = workspaceDict[pKey] ?? (path: session.projectPath, main: [], sub: [])
            if session.isSubagent {
                existing.sub.append(session)
            } else {
                existing.main.append(session)
            }
            workspaceDict[pKey] = existing
        }

        var projectWorkspaces: [AIProjectWorkspace] = []
        for (pName, wData) in workspaceDict {
            let allSess = wData.main + wData.sub
            let sumTokens = allSess.reduce(0) { $0 + $1.tokenUsage.totalTokens }
            let sumCost = allSess.reduce(0.0) { $0 + $1.estimatedCostUSD }
            let sumDur = allSess.reduce(0.0) { $0 + $1.durationSeconds }
            projectWorkspaces.append(AIProjectWorkspace(
                projectName: pName,
                projectPath: wData.path,
                totalTokens: sumTokens,
                totalCostUSD: sumCost,
                totalDurationSeconds: sumDur,
                sessionCount: allSess.count,
                mainSessions: wData.main,
                subagentSessions: wData.sub
            ))
        }
        projectWorkspaces.sort { $0.totalCostUSD > $1.totalCostUSD }

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
            projectWorkspaces: projectWorkspaces,
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
