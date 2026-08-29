import Foundation
import SQLite3

public enum CodexThreadRuntimeState: String, Sendable, Equatable {
    case inProgress
    case completed
    case failed
    case interrupted
    case cancelled
}

public struct CodexRuntimeStatusProbe: Sendable {
    private let databaseURL: URL

    public init(databaseURL: URL? = nil) {
        self.databaseURL = databaseURL
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/thread_history_1.sqlite")
    }

    public func latestThreadStates() -> [String: CodexThreadRuntimeState] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT turns.thread_id, turns.status
            FROM thread_turns AS turns
            INNER JOIN (
                SELECT thread_id, MAX(rollout_ordinal) AS latest_ordinal
                FROM thread_turns
                GROUP BY thread_id
            ) AS latest
              ON latest.thread_id = turns.thread_id
             AND latest.latest_ordinal = turns.rollout_ordinal
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var result: [String: CodexThreadRuntimeState] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idBytes = sqlite3_column_text(statement, 0),
                  let stateBytes = sqlite3_column_text(statement, 1),
                  let state = CodexThreadRuntimeState(rawValue: String(cString: stateBytes)) else { continue }
            result[String(cString: idBytes)] = state
        }
        return result
    }

    public func latestExecutionWorkingDirectories() -> [String: String] {
        var database: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if database != nil { sqlite3_close(database) }
            return [:]
        }
        defer { sqlite3_close(database) }

        let sql = """
            SELECT items.thread_id, items.item_json
            FROM thread_items AS items
            INNER JOIN (
                SELECT thread_id, MAX(rollout_ordinal) AS latest_ordinal
                FROM thread_items
                WHERE item_type = 'commandExecution'
                GROUP BY thread_id
            ) AS latest
              ON latest.thread_id = items.thread_id
             AND latest.latest_ordinal = items.rollout_ordinal
            WHERE items.item_type = 'commandExecution'
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { return [:] }
        defer { sqlite3_finalize(statement) }

        var result: [String: String] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idBytes = sqlite3_column_text(statement, 0),
                  let jsonBytes = sqlite3_column_text(statement, 1),
                  let data = String(cString: jsonBytes).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cwd = object["cwd"] as? String,
                  !cwd.isEmpty else { continue }
            result[String(cString: idBytes)] = cwd
        }
        return result
    }
}

public struct AIProviderProcessEvidence: Sendable, Equatable {
    public let toolType: AIToolType
    public let pid: pid_t
    public let workingDirectory: String
    public let sessionId: String?
    public let cpuPercentage: Double?
    public let memoryBytes: UInt64?

    public init(
        toolType: AIToolType,
        pid: pid_t,
        workingDirectory: String,
        sessionId: String? = nil,
        cpuPercentage: Double? = nil,
        memoryBytes: UInt64? = nil
    ) {
        self.toolType = toolType
        self.pid = pid
        self.workingDirectory = workingDirectory
        self.sessionId = sessionId
        self.cpuPercentage = cpuPercentage
        self.memoryBytes = memoryBytes
    }
}

public enum AISessionRuntimeReconciler {
    public static func reconcile(
        records: [AISessionRecord],
        codexStates: [String: CodexThreadRuntimeState],
        codexExecutionCWDs: [String: String] = [:],
        processes: [AIProviderProcessEvidence],
        now: Date = Date(),
        activityWindow: TimeInterval = 30,
        recentWindow: TimeInterval = 24 * 60 * 60
    ) -> [AISessionRecord] {
        records.map { record in
            if record.toolType == .codex, let state = codexStates[record.sessionId] {
                switch state {
                case .inProgress:
                    return replacing(
                        record,
                        status: .active,
                        source: .providerReported("Codex thread_history_1.sqlite latest turn is inProgress"),
                        projectPath: codexExecutionCWDs[record.sessionId]
                    )
                case .completed:
                    return replacing(
                        record,
                        status: .completed,
                        source: .providerReported("Codex thread_history_1.sqlite latest turn is completed"),
                        projectPath: codexExecutionCWDs[record.sessionId]
                    )
                case .failed, .interrupted, .cancelled:
                    return replacing(
                        record,
                        status: .aborted,
                        source: .providerReported("Codex thread_history_1.sqlite latest turn is \(state.rawValue)"),
                        projectPath: codexExecutionCWDs[record.sessionId]
                    )
                }
            }

            let matchingProcesses = processes.filter { evidence in
                guard evidence.toolType == record.toolType else { return false }
                if let sessionId = evidence.sessionId, sessionId == record.sessionId { return true }
                let processPath = normalizedProjectPath(evidence.workingDirectory)
                let recordPath = normalizedProjectPath(record.projectPath)
                guard !processPath.isEmpty, !recordPath.isEmpty else { return false }
                return processPath == recordPath || processPath.hasPrefix(recordPath + "/")
            }
            if let exact = matchingProcesses.first(where: { $0.sessionId == record.sessionId }) {
                return replacing(
                    record,
                    status: .active,
                    source: .measured("Mac process PID \(exact.pid) exposes this exact provider session ID"),
                    process: exact
                )
            }
            if let process = matchingProcesses.first {
                let age = now.timeIntervalSince(record.lastActiveAt)
                if age <= activityWindow {
                    return replacing(
                        record,
                        status: .active,
                        source: .derived("Mac process PID \(process.pid) CWD matches the project and this transcript changed within \(Int(activityWindow)) seconds"),
                        process: process
                    )
                }
                if age >= recentWindow {
                    return replacing(
                        record,
                        status: .completed,
                        source: .measured("Mac process PID \(process.pid) exists for the project, but project-level CWD cannot identify this historical session")
                    )
                }
                return replacing(
                    record,
                    status: .idle,
                    source: .measured("Mac process PID \(process.pid) is present for the project; this session has no recent transcript activity"),
                    process: process
                )
            }

            return replacing(
                record,
                status: .completed,
                source: .measured("No matching local provider process was found during this refresh")
            )
        }
    }

    public static func processEvidence(from items: [ProcessItem]) -> [AIProviderProcessEvidence] {
        items.compactMap { item in
            guard let context = item.aiContext,
                  let toolType = toolType(named: context.toolName),
                  let workingDirectory = item.workingDirectory,
                  !workingDirectory.isEmpty else { return nil }
            return AIProviderProcessEvidence(
                toolType: toolType,
                pid: item.pid,
                workingDirectory: workingDirectory,
                sessionId: context.sessionId,
                cpuPercentage: item.cpuPercentage,
                memoryBytes: item.memoryBytes
            )
        }
    }

    private static func toolType(named name: String) -> AIToolType? {
        switch name {
        case AIToolType.claudeCode.rawValue: return .claudeCode
        case AIToolType.antigravity.rawValue: return .antigravity
        case AIToolType.codex.rawValue: return .codex
        default: return nil
        }
    }

    private static func normalizedProjectPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        for marker in ["/.claude/worktrees/", "/.codex/worktrees/"] {
            if let range = path.range(of: marker) {
                return URL(fileURLWithPath: String(path[..<range.lowerBound])).standardizedFileURL.path
            }
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func replacing(
        _ record: AISessionRecord,
        status: AISessionStatus,
        source: AIDataProvenance,
        process: AIProviderProcessEvidence? = nil,
        projectPath: String? = nil
    ) -> AISessionRecord {
        let resolvedProjectPath = normalizedProjectPath(projectPath ?? record.projectPath)
        let pathName = URL(fileURLWithPath: resolvedProjectPath).lastPathComponent
        let resolvedProjectName = pathName.isEmpty ? resolvedProjectPath : pathName
        return AISessionRecord(
            sessionId: record.sessionId,
            sessionShortId: record.sessionShortId,
            toolType: record.toolType,
            title: record.title,
            projectName: projectPath == nil ? record.projectName : resolvedProjectName,
            parentProjectName: projectPath == nil ? record.parentProjectName : resolvedProjectName,
            projectPath: resolvedProjectPath,
            gitBranch: record.gitBranch,
            isSubagent: record.isSubagent,
            parentSessionId: record.parentSessionId,
            subagentSlug: record.subagentSlug,
            startedAt: record.startedAt,
            lastActiveAt: record.lastActiveAt,
            durationSeconds: record.durationSeconds,
            status: status,
            statusSource: source,
            livePID: process?.pid,
            liveCPU: process?.cpuPercentage,
            liveMemoryBytes: process?.memoryBytes,
            totalTurns: record.totalTurns,
            totalToolCalls: record.totalToolCalls,
            modelsUsed: record.modelsUsed,
            taskBreakdown: record.taskBreakdown,
            tokenUsage: record.tokenUsage,
            cost: record.cost,
            turns: record.turns
        )
    }
}
