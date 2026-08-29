import Foundation

public final class ClaudeCodeTelemetryParser: @unchecked Sendable {
    public static let shared = ClaudeCodeTelemetryParser()
    private let pricing = AIPricingCalculator.shared
    private let projectsDirectory: URL
    private let persistentCache: AITelemetryFileCache?
    private let cacheLock = NSLock()
    private var cache: [String: (modified: Date, size: Int, record: AISessionRecord)] = [:]

    public init(projectsDirectory: URL? = nil) {
        let usesDefaultDirectory = projectsDirectory == nil
        self.projectsDirectory = projectsDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
        self.persistentCache = usesDefaultDirectory
            ? AITelemetryFileCache(name: "claude-telemetry-cache-v5.json")
            : nil
    }

    public func parseAllSessions(limit: Int? = nil) -> [AISessionRecord] {
        let fileManager = FileManager.default
        var allSessionFiles: [(url: URL, modDate: Date)] = []
        guard let enumerator = fileManager.enumerator(
            at: projectsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            allSessionFiles.append((url: file, modDate: values?.contentModificationDate ?? .distantPast))
        }

        // Sort by most recent
        allSessionFiles.sort { $0.modDate > $1.modDate }

        var sessions: [AISessionRecord] = []
        let selectedFiles = limit.map { Array(allSessionFiles.prefix($0)) } ?? allSessionFiles
        for item in selectedFiles {
            let size = (try? item.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            cacheLock.lock()
            let cached = cache[item.url.path]
            cacheLock.unlock()
            let record: AISessionRecord?
            if cached?.modified == item.modDate, cached?.size == size {
                record = cached?.record
            } else if let persisted = persistentCache?.record(
                path: item.url.path,
                modificationDate: item.modDate,
                fileSize: size
            ) {
                record = persisted
            } else if Date().timeIntervalSince(item.modDate) <= 2 * 60 * 60 {
                record = parseSessionFile(url: item.url)
            } else {
                record = parseSessionMetadataFile(url: item.url, modificationDate: item.modDate)
            }
            if let record {
                cacheLock.lock()
                cache[item.url.path] = (item.modDate, size, record)
                cacheLock.unlock()
                persistentCache?.store(
                    record: record,
                    path: item.url.path,
                    modificationDate: item.modDate,
                    fileSize: size
                )
                sessions.append(record)
            }
        }

        persistentCache?.flush()
        return sessions
    }

    public func parseSessionFile(url: URL) -> AISessionRecord? {
        let filenameSessionId = url.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        var firstCwd: String? = nil
        var gitBranch: String? = nil
        var startedAt: Date?
        var lastActiveAt: Date = Date.distantPast
        var totalDurationMs: Int64 = 0

        var modelMap: [String: (
            turns: Int,
            input: Int64,
            output: Int64,
            cacheRead: Int64,
            cacheWrite5m: Int64,
            cacheWrite1h: Int64,
            unclassifiedCacheWrite: Int64,
            thinking: Int64
        )] = [:]
        var taskMap: [AITaskCategory: (count: Int, durationMs: Int64, input: Int64, output: Int64)] = [:]
        var turns: [AITurnRecord] = []
        var totalToolCalls = 0

        var totalInputTokens: Int64 = 0
        var totalOutputTokens: Int64 = 0
        var totalCacheReadTokens: Int64 = 0
        var totalCacheWriteTokens: Int64 = 0
        var totalThinkingTokens: Int64 = 0
        var hasProviderUsage = false
        var hasBillableUsage = false
        var explicitSessionId: String?
        var agentId: String?
        var isSidechain = false
        var explicitTitle: String?

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in lines {
            guard let jsonData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Extract session metadata from initial line
            if firstCwd == nil, let cwd = obj["cwd"] as? String, !cwd.isEmpty, cwd != "/" {
                firstCwd = cwd
            }
            if explicitSessionId == nil { explicitSessionId = obj["sessionId"] as? String }
            if agentId == nil { agentId = obj["agentId"] as? String }
            if obj["isSidechain"] as? Bool == true { isSidechain = true }
            if let title = (obj["customTitle"] as? String) ?? (obj["summary"] as? String) ?? (obj["slug"] as? String),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                explicitTitle = title
            }
            if gitBranch == nil, let branch = obj["gitBranch"] as? String, !branch.isEmpty {
                gitBranch = branch
            }
            if let timeStr = obj["timestamp"] as? String, let date = dateFormatter.date(from: timeStr) ?? ISO8601DateFormatter().date(from: timeStr) {
                if startedAt == nil || date < startedAt! { startedAt = date }
                if date > lastActiveAt { lastActiveAt = date }
            }

            // Check turn duration entries
            if let subType = obj["subtype"] as? String, subType == "turn_duration",
               let dur = obj["durationMs"] as? Int64 {
                totalDurationMs += dur
            }

            // Extract message usage and tools
            if let msg = obj["message"] as? [String: Any] {
                let model = (msg["model"] as? String) ?? "Unknown Claude model"
                var inTokens: Int64 = 0
                var outTokens: Int64 = 0
                var cacheRead: Int64 = 0
                var cacheWrite: Int64 = 0
                var cacheWrite5m: Int64 = 0
                var cacheWrite1h: Int64 = 0
                var unclassifiedCacheWrite: Int64 = 0
                var thinking: Int64 = 0
                var hasMessageUsage = false

                if let usage = msg["usage"] as? [String: Any] {
                    hasProviderUsage = true
                    hasMessageUsage = true
                    inTokens = Self.int64(usage["input_tokens"])
                    outTokens = Self.int64(usage["output_tokens"])
                    cacheRead = Self.int64(usage["cache_read_input_tokens"])
                    cacheWrite = Self.int64(usage["cache_creation_input_tokens"])
                    if let cacheCreation = usage["cache_creation"] as? [String: Any] {
                        cacheWrite5m = Self.int64(cacheCreation["ephemeral_5m_input_tokens"])
                        cacheWrite1h = Self.int64(cacheCreation["ephemeral_1h_input_tokens"])
                    }
                    unclassifiedCacheWrite = max(0, cacheWrite - cacheWrite5m - cacheWrite1h)
                    if let details = usage["output_tokens_details"] as? [String: Any] {
                        thinking = Self.int64(details["thinking_tokens"])
                    }
                    hasMessageUsage = inTokens > 0
                        || outTokens > 0
                        || cacheRead > 0
                        || cacheWrite > 0
                    hasBillableUsage = hasBillableUsage || hasMessageUsage
                }

                totalInputTokens += inTokens
                totalOutputTokens += outTokens
                totalCacheReadTokens += cacheRead
                totalCacheWriteTokens += cacheWrite
                totalThinkingTokens += thinking

                if hasMessageUsage {
                    var currentModel = modelMap[model] ?? (
                        turns: 0, input: 0, output: 0, cacheRead: 0,
                        cacheWrite5m: 0, cacheWrite1h: 0,
                        unclassifiedCacheWrite: 0, thinking: 0
                    )
                    currentModel.turns += 1
                    currentModel.input += inTokens
                    currentModel.output += outTokens
                    currentModel.cacheRead += cacheRead
                    currentModel.cacheWrite5m += cacheWrite5m
                    currentModel.cacheWrite1h += cacheWrite1h
                    currentModel.unclassifiedCacheWrite += unclassifiedCacheWrite
                    currentModel.thinking += thinking
                    modelMap[model] = currentModel
                }

                // Parse content for tools
                var turnTaskCat: AITaskCategory = thinking > 0 ? .planning : .other
                var turnTaskDesc = "AI 思考與推理"

                if let contentArr = msg["content"] as? [[String: Any]] {
                    for item in contentArr {
                        if let type = item["type"] as? String {
                            if type == "tool_use" {
                                totalToolCalls += 1
                                let toolName = (item["name"] as? String) ?? "tool"
                                let inputObj = item["input"] as? [String: Any]

                                switch toolName.lowercased() {
                                case "bash", "terminal", "run_command":
                                    let cmd = (inputObj?["command"] as? String) ?? (inputObj?["CommandLine"] as? String) ?? ""
                                    if cmd.contains("test") || cmd.contains("pytest") || cmd.contains("swift test") || cmd.contains("jest") {
                                        turnTaskCat = .testing
                                        turnTaskDesc = "執行測試: \(cmd.prefix(60))"
                                    } else if cmd.contains("git ") {
                                        turnTaskCat = .bashCommand
                                        turnTaskDesc = "Git 操作: \(cmd.prefix(60))"
                                    } else {
                                        turnTaskCat = .bashCommand
                                        turnTaskDesc = "執行終端指令: \(cmd.prefix(60))"
                                    }
                                case "fileedit", "edit", "replace_file_content", "write_to_file":
                                    let path = (inputObj?["file_path"] as? String) ?? (inputObj?["TargetFile"] as? String) ?? ""
                                    let fname = URL(fileURLWithPath: path).lastPathComponent
                                    turnTaskCat = .codeEdit
                                    turnTaskDesc = "代碼修改: \(fname)"
                                case "grep", "grep_search", "find_by_name", "view_file", "view":
                                    turnTaskCat = .codeSearch
                                    turnTaskDesc = "搜尋與檢索代碼: \(toolName)"
                                case "websearch", "read_url_content":
                                    turnTaskCat = .web
                                    turnTaskDesc = "查閱網路與文檔"
                                default:
                                    turnTaskCat = .other
                                    turnTaskDesc = "調用工具: \(toolName)"
                                }
                            } else if type == "thinking" {
                                turnTaskCat = .planning
                                turnTaskDesc = "深度架構思考 (Thinking)"
                            }
                        }
                    }
                }

                // Record Turn
                let turnRecord = AITurnRecord(
                    turnIndex: turns.count + 1,
                    timestamp: lastActiveAt,
                    durationMs: 0,
                    modelName: model,
                    taskCategory: turnTaskCat,
                    taskDescription: turnTaskDesc,
                    inputTokens: inTokens,
                    outputTokens: outTokens,
                    cacheReadTokens: cacheRead
                )
                turns.append(turnRecord)

                var catUsage = taskMap[turnTaskCat] ?? (count: 0, durationMs: 0, input: 0, output: 0)
                catUsage.count += 1
                catUsage.input += inTokens
                catUsage.output += outTokens
                taskMap[turnTaskCat] = catUsage
            }
        }

        // Aggregate models
        var modelsUsed: [AIModelUsage] = []
        var totalCost: Double = 0.0
        var hasMissingPrice = false

        for (mName, usage) in modelMap {
            let calculatedCost = usage.unclassifiedCacheWrite == 0
                ? pricing.calculateCostUSD(
                    model: mName,
                    inputTokens: usage.input,
                    outputTokens: usage.output,
                    cacheReadTokens: usage.cacheRead,
                    cacheWriteTokens: usage.cacheWrite5m,
                    cacheWrite1hTokens: usage.cacheWrite1h,
                    thinkingTokens: usage.thinking
                )
                : nil
            if calculatedCost == nil { hasMissingPrice = true }
            let cost = calculatedCost ?? 0
            totalCost += cost
            modelsUsed.append(AIModelUsage(
                modelName: mName,
                turnCount: usage.turns,
                inputTokens: usage.input,
                outputTokens: usage.output,
                cacheReadTokens: usage.cacheRead,
                thinkingTokens: usage.thinking,
                estimatedCostUSD: cost
            ))
        }

        // Aggregate tasks
        var taskBreakdown: [AITaskCategoryUsage] = []
        let totalTokens = totalInputTokens + totalOutputTokens + totalCacheReadTokens

        for (cat, usage) in taskMap {
            let catTokens = usage.input + usage.output
            let share = totalTokens > 0 ? Double(catTokens) / Double(totalTokens) : 0.0
            let catCost = totalCost * share

            taskBreakdown.append(AITaskCategoryUsage(
                category: cat,
                callCount: usage.count,
                totalDurationMs: usage.durationMs,
                tokenShare: share,
                estimatedCostUSD: catCost
            ))
        }
        taskBreakdown.sort { $0.estimatedCostUSD > $1.estimatedCostUSD }

        let fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            ?? .distantPast
        let actualLastActiveAt = lastActiveAt == .distantPast ? fileModificationDate : lastActiveAt
        let actualStartedAt = startedAt ?? actualLastActiveAt
        let durationSec: TimeInterval = totalDurationMs > 0 ? Double(totalDurationMs) / 1000.0 : 0

        let folderName = url.deletingLastPathComponent().lastPathComponent
        let identity = resolveProjectIdentity(folderName: folderName, firstCwd: firstCwd)
        let childSessionId = agentId ?? filenameSessionId.replacingOccurrences(of: "agent-", with: "")
        let recordSessionId = isSidechain ? childSessionId : (explicitSessionId ?? filenameSessionId)
        let parentSessionId = isSidechain ? explicitSessionId : nil

        let tokenSummary = hasProviderUsage
            ? AITokenUsageSummary(
                inputTokens: totalInputTokens,
                outputTokens: totalOutputTokens,
                cacheReadTokens: totalCacheReadTokens,
                cacheWriteTokens: totalCacheWriteTokens,
                thinkingTokens: totalThinkingTokens
            )
            : .unavailable

        return AISessionRecord(
            sessionId: recordSessionId,
            sessionShortId: String(recordSessionId.prefix(8)),
            toolType: .claudeCode,
            title: explicitTitle ?? (isSidechain ? "Claude Subagent \(childSessionId)" : "Claude Session \(String(recordSessionId.prefix(8)))"),
            projectName: identity.parentProjectName,
            parentProjectName: identity.parentProjectName,
            projectPath: identity.projectPath,
            gitBranch: gitBranch,
            isSubagent: isSidechain,
            parentSessionId: parentSessionId,
            subagentSlug: isSidechain ? childSessionId : nil,
            startedAt: actualStartedAt,
            lastActiveAt: actualLastActiveAt,
            durationSeconds: durationSec,
            status: .unknown,
            statusSource: .unavailable("Claude transcript files contain activity, not an authoritative live task state"),
            totalTurns: turns.count,
            totalToolCalls: totalToolCalls,
            modelsUsed: modelsUsed,
            taskBreakdown: taskBreakdown,
            tokenUsage: tokenSummary,
            cost: !hasProviderUsage || !hasBillableUsage
                ? .unavailable(reason: "Provider log does not expose positive billable token usage")
                : hasMissingPrice
                ? .unavailable(reason: "API-equivalent estimate unavailable: exact model rate or cache-write TTL is missing")
                : .apiEquivalentEstimate(
                    totalCost,
                    source: "Official Anthropic API standard token rates captured \(AIPricingCalculator.rateCardDate); API-equivalent estimate, not billing or subscription spend"
                ),
            // Do not persist raw turn descriptions or command excerpts in the
            // dashboard history/cache. Aggregates above are sufficient for UI.
            turns: []
        )
    }

    private func parseSessionMetadataFile(url: URL, modificationDate: Date) -> AISessionRecord? {
        guard let content = Self.readHeadAndTail(url) else { return nil }
        var cwd: String?
        var mainSessionId: String?
        var agentId: String?
        var isSidechain = url.path.contains("/subagents/")
        var branch: String?
        var firstDate: Date?
        var lastDate: Date?
        var explicitTitle: String?
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for line in content.split(whereSeparator: { $0.isNewline }) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            cwd = cwd ?? (object["cwd"] as? String)
            mainSessionId = mainSessionId ?? (object["sessionId"] as? String)
            agentId = agentId ?? (object["agentId"] as? String)
            branch = branch ?? (object["gitBranch"] as? String)
            if object["isSidechain"] as? Bool == true { isSidechain = true }
            if let title = (object["customTitle"] as? String) ?? (object["summary"] as? String) ?? (object["slug"] as? String),
               !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                explicitTitle = title
            }
            if let value = object["timestamp"] as? String,
               let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) {
                if firstDate == nil || date < firstDate! { firstDate = date }
                if lastDate == nil || date > lastDate! { lastDate = date }
            }
        }

        let filenameId = url.deletingPathExtension().lastPathComponent
        let childId = agentId ?? filenameId.replacingOccurrences(of: "agent-", with: "")
        let recordId = isSidechain ? childId : (mainSessionId ?? filenameId)
        let folderName = url.pathComponents.first(where: { $0.hasPrefix("-Users-") })
            ?? url.deletingLastPathComponent().lastPathComponent
        let identity = resolveProjectIdentity(folderName: folderName, firstCwd: cwd)
        let start = firstDate ?? modificationDate
        // Prefer the provider timestamp. The filesystem modification date is only
        // a fallback when the bounded metadata read contains no timestamp.
        let end = lastDate ?? modificationDate

        return AISessionRecord(
            sessionId: recordId,
            toolType: .claudeCode,
            title: explicitTitle ?? (isSidechain ? "Claude Subagent \(childId)" : "Claude Session \(String(recordId.prefix(8)))"),
            projectName: identity.parentProjectName,
            parentProjectName: identity.parentProjectName,
            projectPath: identity.projectPath,
            gitBranch: branch,
            isSubagent: isSidechain,
            parentSessionId: isSidechain ? mainSessionId : nil,
            subagentSlug: isSidechain ? childId : nil,
            startedAt: start,
            lastActiveAt: end,
            durationSeconds: 0,
            status: .unknown,
            statusSource: .unavailable("Historical Claude transcript has no authoritative live task state"),
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable,
            turns: []
        )
    }

    private static func readHeadAndTail(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let chunk: UInt64 = 64 * 1024
        if size <= chunk * 2 {
            try? handle.seek(toOffset: 0)
            guard let data = try? handle.readToEnd() else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: Int(chunk))) ?? Data()
        try? handle.seek(toOffset: size - chunk)
        let tail = (try? handle.readToEnd()) ?? Data()
        guard let headText = String(data: head, encoding: .utf8),
              let tailText = String(data: tail, encoding: .utf8) else { return nil }
        return headText + "\n" + tailText
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let integer = value as? Int64 { return integer }
        if let integer = value as? Int { return Int64(integer) }
        return 0
    }

    private func resolveProjectIdentity(folderName: String, firstCwd: String?) -> (projectName: String, parentProjectName: String, isSubagent: Bool, subagentSlug: String?, projectPath: String) {
        if let cwd = firstCwd, !cwd.isEmpty, cwd != "/" {
            if cwd.hasPrefix(NSHomeDirectory() + "/.claude/") {
                return ("Unlinked Claude Runtime", "Unlinked Claude Runtime", false, nil, "")
            }
            var projectPath = URL(fileURLWithPath: cwd).standardizedFileURL.path
            if let range = projectPath.range(of: "/.claude/worktrees/") {
                projectPath = String(projectPath[..<range.lowerBound])
            }
            let name = URL(fileURLWithPath: projectPath).lastPathComponent
            return (name, name.isEmpty ? "Workspace" : name, false, nil, projectPath)
        }

        // Claude's encoded folder name is not a reversible filesystem path
        // because hyphens can represent both separators and literal characters.
        // Without cwd, keep it unlinked instead of inventing a project.
        return ("Unlinked Claude Metadata", "Unlinked Claude Metadata", false, nil, "")
    }
}
