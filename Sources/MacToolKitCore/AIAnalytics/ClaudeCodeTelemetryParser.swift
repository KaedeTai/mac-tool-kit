import Foundation

public final class ClaudeCodeTelemetryParser: Sendable {
    public static let shared = ClaudeCodeTelemetryParser()
    private let pricing = AIPricingCalculator.shared

    public init() {}

    public func parseAllSessions(limit: Int = 30) -> [AISessionRecord] {
        let fileManager = FileManager.default
        let homeDir = NSHomeDirectory()
        let projectsDir = URL(fileURLWithPath: "\(homeDir)/.claude/projects")

        guard let projectFolders = try? fileManager.contentsOfDirectory(at: projectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var candidateFiles: [(url: URL, modDate: Date)] = []

        for folder in projectFolders {
            guard let files = try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            let jsonlFiles = files.filter { $0.pathExtension == "jsonl" }
            for jsonl in jsonlFiles {
                let modDate = (try? jsonl.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                candidateFiles.append((jsonl, modDate))
            }
        }

        // Sort by modification date and take top 25 most recent files
        candidateFiles.sort { $0.modDate > $1.modDate }
        let topFiles = candidateFiles.prefix(limit)

        var sessions: [AISessionRecord] = []
        for item in topFiles {
            if let record = parseSessionFile(url: item.url) {
                sessions.append(record)
            }
        }

        sessions.sort { $0.lastActiveAt > $1.lastActiveAt }
        return sessions
    }

    public func parseSessionFile(url: URL) -> AISessionRecord? {
        let sessionId = url.deletingPathExtension().lastPathComponent
        guard sessionId.count >= 8 else { return nil }

        // Read efficiently with maximum 2MB slice if file is huge
        guard let fileHandle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fileHandle.close() }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let data: Data
        if fileSize > 2_000_000 {
            // Read tail 2MB
            let offset = max(0, UInt64(fileSize - 2_000_000))
            try? fileHandle.seek(toOffset: offset)
            data = fileHandle.readDataToEndOfFile()
        } else {
            data = fileHandle.readDataToEndOfFile()
        }

        guard let content = String(data: data, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        var projectName = "Workspace"
        var projectPath = ""
        var gitBranch: String? = nil
        var startedAt: Date = Date()
        var lastActiveAt: Date = Date.distantPast
        var totalDurationMs: Int64 = 0

        var modelMap: [String: (turns: Int, input: Int64, output: Int64, cacheRead: Int64, thinking: Int64)] = [:]
        var taskMap: [AITaskCategory: (count: Int, durationMs: Int64, input: Int64, output: Int64)] = [:]
        var turns: [AITurnRecord] = []
        var totalToolCalls = 0

        var totalInputTokens: Int64 = 0
        var totalOutputTokens: Int64 = 0
        var totalCacheReadTokens: Int64 = 0
        var totalCacheWriteTokens: Int64 = 0
        var totalThinkingTokens: Int64 = 0

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for (index, line) in lines.enumerated() {
            guard let jsonData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            // Extract session metadata from line
            if let cwd = obj["cwd"] as? String, !cwd.isEmpty {
                projectPath = cwd
                projectName = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if let branch = obj["gitBranch"] as? String, !branch.isEmpty {
                gitBranch = branch
            }
            if let timeStr = obj["timestamp"] as? String, let date = dateFormatter.date(from: timeStr) ?? ISO8601DateFormatter().date(from: timeStr) {
                if index == 0 { startedAt = date }
                if date > lastActiveAt { lastActiveAt = date }
            }

            // Check turn duration entries
            if let subType = obj["subtype"] as? String, subType == "turn_duration",
               let dur = obj["durationMs"] as? Int64 {
                totalDurationMs += dur
            }

            // Extract message usage and tools
            if let msg = obj["message"] as? [String: Any] {
                let model = (msg["model"] as? String) ?? "claude-3-7-sonnet"
                var inTokens: Int64 = 0
                var outTokens: Int64 = 0
                var cacheRead: Int64 = 0
                var cacheWrite: Int64 = 0
                var thinking: Int64 = 0

                if let usage = msg["usage"] as? [String: Any] {
                    inTokens = Int64((usage["input_tokens"] as? Int) ?? 0)
                    outTokens = Int64((usage["output_tokens"] as? Int) ?? 0)
                    cacheRead = Int64((usage["cache_read_input_tokens"] as? Int) ?? 0)
                    cacheWrite = Int64((usage["cache_creation_input_tokens"] as? Int) ?? 0)
                    if let details = usage["output_tokens_details"] as? [String: Any] {
                        thinking = Int64((details["thinking_tokens"] as? Int) ?? 0)
                    }
                }

                totalInputTokens += inTokens
                totalOutputTokens += outTokens
                totalCacheReadTokens += cacheRead
                totalCacheWriteTokens += cacheWrite
                totalThinkingTokens += thinking

                var current = modelMap[model] ?? (turns: 0, input: 0, output: 0, cacheRead: 0, thinking: 0)
                current.turns += 1
                current.input += inTokens
                current.output += outTokens
                current.cacheRead += cacheRead
                current.thinking += thinking
                modelMap[model] = current

                // Tool detection in content
                var taskCat: AITaskCategory = .planning
                var taskDesc = "思考與規劃架構"

                if let contentArr = msg["content"] as? [[String: Any]] {
                    for item in contentArr {
                        if let type = item["type"] as? String, type == "tool_use" {
                            totalToolCalls += 1
                            let toolName = (item["name"] as? String) ?? "Tool"
                            let input = (item["input"] as? [String: Any]) ?? [:]

                            if toolName.lowercased().contains("bash") || toolName.lowercased().contains("command") {
                                let cmd = (input["command"] as? String) ?? ""
                                if cmd.contains("pytest") || cmd.contains("test") || cmd.contains("cargo test") || cmd.contains("swift test") {
                                    taskCat = .testing
                                    taskDesc = "執行單元測試: \(cmd.prefix(40))"
                                } else {
                                    taskCat = .bashCommand
                                    taskDesc = "終端指令: \(cmd.prefix(40))"
                                }
                            } else if toolName.lowercased().contains("edit") || toolName.lowercased().contains("replace") || toolName.lowercased().contains("write") {
                                taskCat = .codeEdit
                                let target = (input["target_file"] as? String) ?? (input["TargetFile"] as? String) ?? "代碼檔案"
                                taskDesc = "修改代碼: \(URL(fileURLWithPath: target).lastPathComponent)"
                            } else if toolName.lowercased().contains("grep") || toolName.lowercased().contains("search") || toolName.lowercased().contains("view") || toolName.lowercased().contains("read") {
                                taskCat = .codeSearch
                                taskDesc = "搜尋代碼庫: \(toolName)"
                            } else if toolName.lowercased().contains("web") || toolName.lowercased().contains("url") {
                                taskCat = .web
                                taskDesc = "網頁查閱: \(toolName)"
                            } else {
                                taskCat = .other
                                taskDesc = "呼叫工具: \(toolName)"
                            }
                        }
                    }
                }

                var taskUsage = taskMap[taskCat] ?? (count: 0, durationMs: 0, input: 0, output: 0)
                taskUsage.count += 1
                taskUsage.input += inTokens
                taskUsage.output += outTokens
                taskMap[taskCat] = taskUsage

                let turnDate = (obj["timestamp"] as? String).flatMap { dateFormatter.date(from: $0) } ?? startedAt
                turns.append(AITurnRecord(
                    turnIndex: turns.count + 1,
                    timestamp: turnDate,
                    durationMs: 0,
                    modelName: model,
                    taskCategory: taskCat,
                    taskDescription: taskDesc,
                    inputTokens: inTokens,
                    outputTokens: outTokens,
                    cacheReadTokens: cacheRead,
                    thinkingTokens: thinking
                ))
            }
        }

        if lastActiveAt == Date.distantPast {
            lastActiveAt = startedAt
        }

        let durationSec = totalDurationMs > 0 ? TimeInterval(totalDurationMs) / 1000.0 : max(1.0, lastActiveAt.timeIntervalSince(startedAt))

        // Aggregate models
        var modelsUsed: [AIModelUsage] = []
        var totalCost: Double = 0.0

        for (mName, mStats) in modelMap {
            let cost = pricing.calculateCostUSD(
                model: mName,
                inputTokens: mStats.input,
                outputTokens: mStats.output,
                cacheReadTokens: mStats.cacheRead,
                thinkingTokens: mStats.thinking
            )
            totalCost += cost
            modelsUsed.append(AIModelUsage(
                modelName: mName,
                turnCount: mStats.turns,
                inputTokens: mStats.input,
                outputTokens: mStats.output,
                cacheReadTokens: mStats.cacheRead,
                thinkingTokens: mStats.thinking,
                estimatedCostUSD: cost
            ))
        }

        // Aggregate task categories
        let totalTaskTokens = max(1, totalInputTokens + totalOutputTokens)
        var taskBreakdown: [AITaskCategoryUsage] = []

        for (cat, stats) in taskMap {
            let taskTokens = stats.input + stats.output
            let share = Double(taskTokens) / Double(totalTaskTokens)
            let taskCost = totalCost * share
            taskBreakdown.append(AITaskCategoryUsage(
                category: cat,
                callCount: stats.count,
                totalDurationMs: stats.durationMs,
                tokenShare: share,
                estimatedCostUSD: taskCost
            ))
        }

        // Sort breakdowns
        modelsUsed.sort { $0.turnCount > $1.turnCount }
        taskBreakdown.sort { $0.callCount > $1.callCount }

        let tokenSummary = AITokenUsageSummary(
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheReadTokens: totalCacheReadTokens,
            cacheWriteTokens: totalCacheWriteTokens,
            thinkingTokens: totalThinkingTokens
        )

        return AISessionRecord(
            sessionId: sessionId,
            sessionShortId: String(sessionId.prefix(8)),
            toolType: .claudeCode,
            projectName: projectName,
            projectPath: projectPath,
            gitBranch: gitBranch,
            startedAt: startedAt,
            lastActiveAt: lastActiveAt,
            durationSeconds: durationSec,
            status: .completed,
            totalTurns: turns.count,
            totalToolCalls: totalToolCalls,
            modelsUsed: modelsUsed,
            taskBreakdown: taskBreakdown,
            tokenUsage: tokenSummary,
            estimatedCostUSD: totalCost,
            turns: turns
        )
    }
}
