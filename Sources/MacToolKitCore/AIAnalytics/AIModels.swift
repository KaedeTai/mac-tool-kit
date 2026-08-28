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
    case active = "執行中 (Active)"
    case thinking = "深度推理 (Thinking)"
    case executingTool = "呼叫工具 (Tool Executing)"
    case idle = "等待輸入 (Idle)"
    case completed = "已完成 (Completed)"
    case aborted = "已終止 (Aborted)"

    public var id: String { rawValue }

    public var statusColorName: String {
        switch self {
        case .active, .executingTool: return "blue"
        case .thinking: return "purple"
        case .idle: return "green"
        case .completed: return "secondary"
        case .aborted: return "red"
        }
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

    public init(
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cacheReadTokens: Int64 = 0,
        cacheWriteTokens: Int64 = 0,
        thinkingTokens: Int64 = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.thinkingTokens = thinkingTokens
        self.totalTokens = inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens + thinkingTokens
    }
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
public struct AISessionRecord: Identifiable, Sendable {
    public var id: String { sessionId }
    public let sessionId: String
    public let sessionShortId: String
    public let toolType: AIToolType
    public let projectName: String
    public let parentProjectName: String
    public let projectPath: String
    public let gitBranch: String?
    public let isSubagent: Bool
    public let subagentSlug: String?
    public let startedAt: Date
    public let lastActiveAt: Date
    public let durationSeconds: TimeInterval
    public let status: AISessionStatus
    public let livePID: pid_t?
    public let liveCPU: Double?
    public let liveMemoryBytes: UInt64?

    public let totalTurns: Int
    public let totalToolCalls: Int
    public let modelsUsed: [AIModelUsage]
    public let taskBreakdown: [AITaskCategoryUsage]
    public let tokenUsage: AITokenUsageSummary
    public let estimatedCostUSD: Double
    public let turns: [AITurnRecord]

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
        projectName: String,
        parentProjectName: String? = nil,
        projectPath: String,
        gitBranch: String? = nil,
        isSubagent: Bool = false,
        subagentSlug: String? = nil,
        startedAt: Date,
        lastActiveAt: Date,
        durationSeconds: TimeInterval,
        status: AISessionStatus,
        livePID: pid_t? = nil,
        liveCPU: Double? = nil,
        liveMemoryBytes: UInt64? = nil,
        totalTurns: Int,
        totalToolCalls: Int,
        modelsUsed: [AIModelUsage],
        taskBreakdown: [AITaskCategoryUsage],
        tokenUsage: AITokenUsageSummary,
        estimatedCostUSD: Double,
        turns: [AITurnRecord] = []
    ) {
        self.sessionId = sessionId
        self.sessionShortId = sessionShortId ?? String(sessionId.prefix(8))
        self.toolType = toolType
        self.projectName = projectName
        self.parentProjectName = parentProjectName ?? projectName
        self.projectPath = projectPath
        self.gitBranch = gitBranch
        self.isSubagent = isSubagent
        self.subagentSlug = subagentSlug
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.livePID = livePID
        self.liveCPU = liveCPU
        self.liveMemoryBytes = liveMemoryBytes
        self.totalTurns = totalTurns
        self.totalToolCalls = totalToolCalls
        self.modelsUsed = modelsUsed
        self.taskBreakdown = taskBreakdown
        self.tokenUsage = tokenUsage
        self.estimatedCostUSD = estimatedCostUSD
        self.turns = turns
    }
}

// MARK: - Hierarchical Project Workspace Group
public struct AIProjectWorkspace: Identifiable, Sendable {
    public var id: String { projectName }
    public let projectName: String
    public let projectPath: String
    public let totalTokens: Int64
    public let totalCostUSD: Double
    public let totalDurationSeconds: TimeInterval
    public let sessionCount: Int
    public let mainSessions: [AISessionRecord]
    public let subagentSessions: [AISessionRecord]

    public var hasLiveActive: Bool {
        mainSessions.contains(where: { $0.livePID != nil }) ||
        subagentSessions.contains(where: { $0.livePID != nil })
    }

    public init(
        projectName: String,
        projectPath: String,
        totalTokens: Int64,
        totalCostUSD: Double,
        totalDurationSeconds: TimeInterval,
        sessionCount: Int,
        mainSessions: [AISessionRecord],
        subagentSessions: [AISessionRecord]
    ) {
        self.projectName = projectName
        self.projectPath = projectPath
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.totalDurationSeconds = totalDurationSeconds
        self.sessionCount = sessionCount
        self.mainSessions = mainSessions
        self.subagentSessions = subagentSessions
    }
}

// MARK: - Project Aggregated Metrics
public struct AIProjectSummary: Identifiable, Sendable {
    public var id: String { projectName }
    public let projectName: String
    public let sessionCount: Int
    public let totalTokens: Int64
    public let totalCostUSD: Double
    public let totalDurationSeconds: TimeInterval

    public init(projectName: String, sessionCount: Int, totalTokens: Int64, totalCostUSD: Double, totalDurationSeconds: TimeInterval) {
        self.projectName = projectName
        self.sessionCount = sessionCount
        self.totalTokens = totalTokens
        self.totalCostUSD = totalCostUSD
        self.totalDurationSeconds = totalDurationSeconds
    }
}

// MARK: - Overall Telemetry Summary
public struct AIAnalyticsSummary: Sendable {
    public let activeSessions: [AISessionRecord]
    public let projectWorkspaces: [AIProjectWorkspace]
    public let recentSessions: [AISessionRecord]
    public let totalSessionsCount: Int
    public let totalDurationSeconds: TimeInterval
    public let totalTokensAllTime: Int64
    public let totalCostUSDAllTime: Double
    public let totalTokensToday: Int64
    public let totalCostUSDToday: Double
    public let topProjects: [AIProjectSummary]
    public let allModelsUsed: [AIModelUsage]
    public let allTasksBreakdown: [AITaskCategoryUsage]

    public init(
        activeSessions: [AISessionRecord] = [],
        projectWorkspaces: [AIProjectWorkspace] = [],
        recentSessions: [AISessionRecord] = [],
        totalSessionsCount: Int = 0,
        totalDurationSeconds: TimeInterval = 0,
        totalTokensAllTime: Int64 = 0,
        totalCostUSDAllTime: Double = 0,
        totalTokensToday: Int64 = 0,
        totalCostUSDToday: Double = 0,
        topProjects: [AIProjectSummary] = [],
        allModelsUsed: [AIModelUsage] = [],
        allTasksBreakdown: [AITaskCategoryUsage] = []
    ) {
        self.activeSessions = activeSessions
        self.projectWorkspaces = projectWorkspaces
        self.recentSessions = recentSessions
        self.totalSessionsCount = totalSessionsCount
        self.totalDurationSeconds = totalDurationSeconds
        self.totalTokensAllTime = totalTokensAllTime
        self.totalCostUSDAllTime = totalCostUSDAllTime
        self.totalTokensToday = totalTokensToday
        self.totalCostUSDToday = totalCostUSDToday
        self.topProjects = topProjects
        self.allModelsUsed = allModelsUsed
        self.allTasksBreakdown = allTasksBreakdown
    }
}
