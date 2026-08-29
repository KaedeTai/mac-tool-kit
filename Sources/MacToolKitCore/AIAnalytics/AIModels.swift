import Foundation

// MARK: - AI Tool Enums
public enum AIToolType: String, Codable, Sendable, CaseIterable, Identifiable {
    case claudeCode = "Claude Code"
    case antigravity = "Antigravity Agent"
    case codex = "OpenAI Codex"
    case cursor = "Cursor AI"
    case ollama = "Ollama / Local LLM"
    case other = "AI Agent"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .claudeCode: return "terminal.fill"
        case .antigravity: return "brain.head.profile"
        case .codex: return "cube.transparent.fill"
        case .cursor: return "chevron.left.forwardslash.chevron.right"
        case .ollama: return "cpu"
        case .other: return "sparkles"
        }
    }
}

public enum AISessionStatus: String, Codable, Sendable, CaseIterable, Identifiable {
    case unknown = "狀態不明 (Unknown)"
    case active = "執行中 (Active)"
    case thinking = "深度推理 (Thinking)"
    case executingTool = "呼叫工具 (Tool Executing)"
    case idle = "程序存在（Idle）"
    case completed = "非執行中 (Inactive)"
    case aborted = "已終止 (Aborted)"

    public var id: String { rawValue }

    public var statusColorName: String {
        switch self {
        case .unknown: return "orange"
        case .active, .executingTool: return "blue"
        case .thinking: return "purple"
        case .idle: return "green"
        case .completed: return "secondary"
        case .aborted: return "red"
        }
    }
}

public enum AIDataProvenance: Codable, Sendable, Equatable {
    case measured(String)
    case providerReported(String)
    case derived(String)
    case estimated(String)
    case unavailable(String)

    public var label: String {
        switch self {
        case .measured: return "實測"
        case .providerReported: return "供應商回報"
        case .derived: return "衍生"
        case .estimated: return "估算"
        case .unavailable: return "不可取得"
        }
    }

    public var detail: String {
        switch self {
        case .measured(let detail), .providerReported(let detail), .derived(let detail),
             .estimated(let detail), .unavailable(let detail):
            return detail
        }
    }
}

public enum AICostKind: String, Codable, Sendable, Equatable {
    case actualBilling
    case apiEquivalentEstimate
    case unavailable
}

public struct AICostValue: Codable, Sendable, Equatable {
    public let amountUSD: Double?
    public let kind: AICostKind
    public let source: AIDataProvenance

    public init(amountUSD: Double?, kind: AICostKind, source: AIDataProvenance) {
        self.amountUSD = amountUSD
        self.kind = kind
        self.source = source
    }

    public static let unavailable = AICostValue(
        amountUSD: nil,
        kind: .unavailable,
        source: .unavailable("Provider log does not include billing or credit charges")
    )

    public static func unavailable(reason: String) -> AICostValue {
        AICostValue(amountUSD: nil, kind: .unavailable, source: .unavailable(reason))
    }

    public static func apiEquivalentEstimate(_ amountUSD: Double, source: String) -> AICostValue {
        AICostValue(amountUSD: amountUSD, kind: .apiEquivalentEstimate, source: .estimated(source))
    }
}

public enum AISessionLifecycle: String, Codable, Sendable, Equatable, CaseIterable, Identifiable {
    case active
    case recent
    case history

    public var id: String { rawValue }

    public static func classify(
        status: AISessionStatus,
        lastActiveAt: Date,
        now: Date = Date(),
        recentWindow: TimeInterval = 24 * 60 * 60
    ) -> AISessionLifecycle {
        switch status {
        case .active, .thinking, .executingTool:
            return .active
        case .idle, .unknown, .completed, .aborted:
            return now.timeIntervalSince(lastActiveAt) < recentWindow ? .recent : .history
        }
    }
}

public enum AISessionScopeSelection {
    public static func reconcile(
        current: AISessionRecord?,
        visibleSessions: [AISessionRecord]
    ) -> AISessionRecord? {
        guard let current else { return visibleSessions.first }
        return visibleSessions.first { $0.id == current.id } ?? visibleSessions.first
    }
}

public enum AISessionPresentation {
    /// Active scope must never hide a real runtime record. In recent/history,
    /// metadata-only provider records are optional because they cannot support
    /// model, token, or cost analysis even though their ID and timestamps are real.
    public static func shouldInclude(
        _ session: AISessionRecord,
        lifecycle: AISessionLifecycle,
        showActivityOnlyRecords: Bool
    ) -> Bool {
        lifecycle == .active || showActivityOnlyRecords || !session.isActivityOnlyRecord
    }
}

public enum AITaskCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case testing = "單元測試 (Unit Tests)"
    case codeEdit = "代碼修改 (Code Editing)"
    case codeSearch = "代碼檢索 (Search & Grep)"
    case planning = "架構規劃 (Planning & CoT)"
    case bashCommand = "終端命令 (Terminal / Shell)"
    case web = "網路查閱 (Web & Docs)"
    case other = "一般任務 (General)"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .testing: return "checkmark.diamond.fill"
        case .codeEdit: return "pencil.and.ruler.fill"
        case .codeSearch: return "text.magnifyingglass"
        case .planning: return "lightbulb.fill"
        case .bashCommand: return "terminal"
        case .web: return "globe"
        case .other: return "ellipsis.bubble.fill"
        }
    }
}

// MARK: - Token & Usage Models
public struct AITokenUsageSummary: Codable, Sendable, Equatable {
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let cacheWriteTokens: Int64
    public let thinkingTokens: Int64
    public let totalTokens: Int64
    public let source: AIDataProvenance

    public init(
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        thinkingTokens: Int64 = 0,
        providerTotalTokens: Int64? = nil,
        source: AIDataProvenance = .providerReported("Provider message usage")
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.thinkingTokens = thinkingTokens
        // Cache and reasoning fields can be subsets of input/output for some providers.
        // Prefer the provider's explicit total; otherwise count each provider bucket once.
        self.totalTokens = providerTotalTokens ?? (inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens)
        self.source = source
    }

    public static let unavailable = AITokenUsageSummary(
        providerTotalTokens: 0,
        source: .unavailable("Provider log does not expose token usage")
    )
}

public struct AIModelUsage: Identifiable, Codable, Sendable, Equatable {
    public var id: String { modelName }
    public let modelName: String
    public let turnCount: Int
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let thinkingTokens: Int64
    public let estimatedCostUSD: Double

    public init(
        modelName: String,
        turnCount: Int,
        inputTokens: Int64,
        outputTokens: Int64,
        cacheReadTokens: Int64,
        thinkingTokens: Int64,
        estimatedCostUSD: Double
    ) {
        self.modelName = modelName
        self.turnCount = turnCount
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.thinkingTokens = thinkingTokens
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public struct AITaskCategoryUsage: Identifiable, Codable, Sendable, Equatable {
    public var id: String { category.rawValue }
    public let category: AITaskCategory
    public let callCount: Int
    public let totalDurationMs: Int64
    public let tokenShare: Double
    public let estimatedCostUSD: Double

    public init(
        category: AITaskCategory,
        callCount: Int,
        totalDurationMs: Int64,
        tokenShare: Double,
        estimatedCostUSD: Double
    ) {
        self.category = category
        self.callCount = callCount
        self.totalDurationMs = totalDurationMs
        self.tokenShare = tokenShare
        self.estimatedCostUSD = estimatedCostUSD
    }
}

public struct AITurnRecord: Identifiable, Codable, Sendable, Equatable {
    public var id: String { "\(turnIndex)_\(timestamp.timeIntervalSince1970)" }
    public let turnIndex: Int
    public let timestamp: Date
    public let durationMs: Int64
    public let modelName: String?
    public let taskCategory: AITaskCategory
    public let taskDescription: String
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let thinkingTokens: Int64

    public init(
        turnIndex: Int,
        timestamp: Date,
        durationMs: Int64,
        modelName: String?,
        taskCategory: AITaskCategory,
        taskDescription: String,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        thinkingTokens: Int64 = 0
    ) {
        self.turnIndex = turnIndex
        self.timestamp = timestamp
        self.durationMs = durationMs
        self.modelName = modelName
        self.taskCategory = taskCategory
        self.taskDescription = taskDescription
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.thinkingTokens = thinkingTokens
    }
}

// MARK: - Session Record
public struct AISessionRecord: Identifiable, Codable, Sendable {
    public var id: String { "\(toolType.rawValue):\(sessionId)" }
    public let sessionId: String
    public let sessionShortId: String
    public let toolType: AIToolType
    public let title: String
    public let projectName: String
    public let parentProjectName: String
    public let projectPath: String
    public let gitBranch: String?
    public let isSubagent: Bool
    public let parentSessionId: String?
    public let subagentSlug: String?
    public let startedAt: Date
    public let lastActiveAt: Date
    public let durationSeconds: TimeInterval
    public let status: AISessionStatus
    public let statusSource: AIDataProvenance
    public let livePID: pid_t?
    public let liveCPU: Double?
    public let liveMemoryBytes: UInt64?

    public let totalTurns: Int
    public let totalToolCalls: Int
    public let modelsUsed: [AIModelUsage]
    public let taskBreakdown: [AITaskCategoryUsage]
    public let tokenUsage: AITokenUsageSummary
    public let cost: AICostValue
    public let turns: [AITurnRecord]

    public var lifecycle: AISessionLifecycle {
        AISessionLifecycle.classify(status: status, lastActiveAt: lastActiveAt)
    }

    public var estimatedCostUSD: Double {
        cost.kind == .apiEquivalentEstimate ? (cost.amountUSD ?? 0) : 0
    }

    public var actualCostUSD: Double? {
        cost.kind == .actualBilling ? cost.amountUSD : nil
    }

    public var transcriptSpanSeconds: TimeInterval {
        max(0, lastActiveAt.timeIntervalSince(startedAt))
    }

    public var isActivityOnlyRecord: Bool {
        guard modelsUsed.isEmpty else { return false }
        if case .unavailable = tokenUsage.source { return true }
        return false
    }

    public var formattedDuration: String {
        let total = Int(max(0, durationSeconds))
        if total < 60 {
            return "\(total) 秒"
        } else if total < 3600 {
            return "\(total / 60) 分 \(total % 60) 秒"
        } else {
            let h = total / 3600
            let m = (total % 3600) / 60
            return "\(h) 小時 \(m) 分"
        }
    }

    public var formattedTimeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let startStr = formatter.string(from: startedAt)
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "HH:mm"
        let endStr = endFormatter.string(from: lastActiveAt)
        return "\(startStr) ~ \(endStr) (歷時 \(formattedDuration))"
    }

    public init(
        sessionId: String,
        sessionShortId: String? = nil,
        toolType: AIToolType,
        title: String? = nil,
        projectName: String,
        parentProjectName: String? = nil,
        projectPath: String,
        gitBranch: String? = nil,
        isSubagent: Bool = false,
        parentSessionId: String? = nil,
        subagentSlug: String? = nil,
        startedAt: Date,
        lastActiveAt: Date,
        durationSeconds: TimeInterval,
        status: AISessionStatus,
        statusSource: AIDataProvenance = .unavailable("Provider does not expose a live task status"),
        livePID: pid_t? = nil,
        liveCPU: Double? = nil,
        liveMemoryBytes: UInt64? = nil,
        totalTurns: Int,
        totalToolCalls: Int,
        modelsUsed: [AIModelUsage],
        taskBreakdown: [AITaskCategoryUsage],
        tokenUsage: AITokenUsageSummary,
        cost: AICostValue? = nil,
        estimatedCostUSD: Double? = nil,
        turns: [AITurnRecord] = []
    ) {
        self.sessionId = sessionId
        self.sessionShortId = sessionShortId ?? String(sessionId.prefix(8))
        self.toolType = toolType
        self.title = title ?? projectName
        self.projectName = projectName
        self.parentProjectName = parentProjectName ?? projectName
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.isSubagent = isSubagent
        self.parentSessionId = parentSessionId
        self.subagentSlug = subagentSlug
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.statusSource = statusSource
        self.livePID = livePID
        self.liveCPU = liveCPU
        self.liveMemoryBytes = liveMemoryBytes
        self.totalTurns = totalTurns
        self.totalToolCalls = totalToolCalls
        self.modelsUsed = modelsUsed
        self.taskBreakdown = taskBreakdown
        self.tokenUsage = tokenUsage
        if let cost {
            self.cost = cost
        } else if let estimatedCostUSD {
            self.cost = .apiEquivalentEstimate(
                estimatedCostUSD,
                source: "Local token-rate comparison; not provider billing"
            )
        } else {
            self.cost = .unavailable
        }
        self.turns = turns
    }
}

// MARK: - Hierarchical Project Workspace Group
public struct AIProjectWorkspace: Identifiable, Sendable {
    public var id: String {
        projectPath.isEmpty ? "unlinked:\(projectName)" : projectPath
    }
    public let projectName: String
    public let projectPath: String
    public let totalTokens: Int64
    public let actualCostUSD: Double?
    public let apiEquivalentEstimateUSD: Double?
    public let apiEquivalentEstimateIsComplete: Bool
    public let totalDurationSeconds: TimeInterval
    public let sessionCount: Int
    public let mainSessions: [AISessionRecord]
    public let subagentSessions: [AISessionRecord]
    private let childrenByParentKey: [String: [AISessionRecord]]
    public let unlinkedSubagentSessions: [AISessionRecord]

    public var totalCostUSD: Double { actualCostUSD ?? 0 }

    public var hasLiveActive: Bool {
        (mainSessions + subagentSessions).contains { $0.lifecycle == .active }
    }

    public func children(of mainSession: AISessionRecord) -> [AISessionRecord] {
        childrenByParentKey[Self.parentKey(
            toolType: mainSession.toolType,
            sessionId: mainSession.sessionId
        )] ?? []
    }

    public init(
        projectName: String,
        projectPath: String,
        totalTokens: Int64,
        totalCostUSD: Double = 0,
        actualCostUSD: Double? = nil,
        apiEquivalentEstimateUSD: Double? = nil,
        apiEquivalentEstimateIsComplete: Bool? = nil,
        totalDurationSeconds: TimeInterval,
        sessionCount: Int,
        mainSessions: [AISessionRecord],
        subagentSessions: [AISessionRecord]
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.totalTokens = totalTokens
        self.actualCostUSD = actualCostUSD ?? (totalCostUSD > 0 ? totalCostUSD : nil)
        self.apiEquivalentEstimateUSD = apiEquivalentEstimateUSD
        let tokenBearingSessions = (mainSessions + subagentSessions).filter { session in
            guard session.tokenUsage.totalTokens > 0 else { return false }
            if case .unavailable = session.tokenUsage.source { return false }
            return true
        }
        self.apiEquivalentEstimateIsComplete = apiEquivalentEstimateIsComplete
            ?? (!tokenBearingSessions.isEmpty && tokenBearingSessions.allSatisfy {
                $0.cost.kind == .apiEquivalentEstimate && $0.cost.amountUSD != nil
            })
        self.totalDurationSeconds = totalDurationSeconds
        self.sessionCount = sessionCount
        self.mainSessions = mainSessions
        self.subagentSessions = subagentSessions
        let mainIDs = Set(mainSessions.map {
            Self.parentKey(toolType: $0.toolType, sessionId: $0.sessionId)
        })
        var groupedChildren: [String: [AISessionRecord]] = [:]
        for child in subagentSessions {
            guard let parent = child.parentSessionId else { continue }
            groupedChildren[
                Self.parentKey(toolType: child.toolType, sessionId: parent),
                default: []
            ].append(child)
        }
        self.childrenByParentKey = groupedChildren
        self.unlinkedSubagentSessions = subagentSessions.filter { child in
            guard let parent = child.parentSessionId else { return true }
            return !mainIDs.contains(Self.parentKey(toolType: child.toolType, sessionId: parent))
        }
    }

    private static func parentKey(toolType: AIToolType, sessionId: String) -> String {
        "\(toolType.rawValue)::\(sessionId)"
    }
}

// MARK: - Project Aggregated Metrics
public struct AIProjectSummary: Identifiable, Sendable {
    public var id: String { projectName }
    public let projectName: String
    public let sessionCount: Int
    public let totalTokens: Int64
    public let actualCostUSD: Double?
    public let apiEquivalentEstimateUSD: Double?
    public var totalCostUSD: Double { actualCostUSD ?? 0 }
    public let totalDurationSeconds: TimeInterval

    public init(
        projectName: String,
        sessionCount: Int,
        totalTokens: Int64,
        totalCostUSD: Double = 0,
        actualCostUSD: Double? = nil,
        apiEquivalentEstimateUSD: Double? = nil,
        totalDurationSeconds: TimeInterval
    ) {
        self.projectName = projectName
        self.sessionCount = sessionCount
        self.totalTokens = totalTokens
        self.actualCostUSD = actualCostUSD ?? (totalCostUSD > 0 ? totalCostUSD : nil)
        self.apiEquivalentEstimateUSD = apiEquivalentEstimateUSD
        self.totalDurationSeconds = totalDurationSeconds
    }
}

// MARK: - Overall Telemetry Summary
public struct AIAnalyticsSummary: Sendable {
    public let activeSessions: [AISessionRecord]
    public let projectWorkspaces: [AIProjectWorkspace]
    public let recentSessions: [AISessionRecord]
    public let historySessions: [AISessionRecord]
    public let totalSessionsCount: Int
    public let totalDurationSeconds: TimeInterval
    public let totalTokensAllTime: Int64
    public let totalCostUSDAllTime: Double
    public let totalTokensToday: Int64
    public let totalCostUSDToday: Double
    public let topProjects: [AIProjectSummary]
    public let allModelsUsed: [AIModelUsage]
    public let allTasksBreakdown: [AITaskCategoryUsage]
    public let historyPersistenceStatus: AIDataProvenance

    public init(
        activeSessions: [AISessionRecord] = [],
        projectWorkspaces: [AIProjectWorkspace] = [],
        recentSessions: [AISessionRecord] = [],
        historySessions: [AISessionRecord] = [],
        totalSessionsCount: Int = 0,
        totalDurationSeconds: TimeInterval = 0,
        totalTokensAllTime: Int64 = 0,
        totalCostUSDAllTime: Double = 0,
        totalTokensToday: Int64 = 0,
        totalCostUSDToday: Double = 0,
        topProjects: [AIProjectSummary] = [],
        allModelsUsed: [AIModelUsage] = [],
        allTasksBreakdown: [AITaskCategoryUsage] = [],
        historyPersistenceStatus: AIDataProvenance = .unavailable("History index has not been written yet")
    ) {
        self.activeSessions = activeSessions
        self.projectWorkspaces = projectWorkspaces
        self.recentSessions = recentSessions
        self.historySessions = historySessions
        self.totalSessionsCount = totalSessionsCount
        self.totalDurationSeconds = totalDurationSeconds
        self.totalTokensAllTime = totalTokensAllTime
        self.totalCostUSDAllTime = totalCostUSDAllTime
        self.totalTokensToday = totalTokensToday
        self.totalCostUSDToday = totalCostUSDToday
        self.topProjects = topProjects
        self.allModelsUsed = allModelsUsed
        self.allTasksBreakdown = allTasksBreakdown
        self.historyPersistenceStatus = historyPersistenceStatus
    }
}
