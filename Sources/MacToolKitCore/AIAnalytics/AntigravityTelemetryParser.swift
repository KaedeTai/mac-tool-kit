import Foundation

public final class AntigravityTelemetryParser: Sendable {
    public static let shared = AntigravityTelemetryParser()
    private let pricing = AIPricingCalculator.shared

    public init() {}

    public func parseAllSessions(limit: Int = 30) -> [AISessionRecord] {
        let fileManager = FileManager.default
        let homeDir = NSHomeDirectory()
        let brainDir = URL(fileURLWithPath: "\(homeDir)/.gemini/antigravity/brain")

        guard let convFolders = try? fileManager.contentsOfDirectory(at: brainDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }

        var sessions: [AISessionRecord] = []

        for folder in convFolders {
            let logFile = folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            if fileManager.fileExists(atPath: logFile.path),
               let record = parseTranscriptFile(url: logFile, conversationId: folder.lastPathComponent) {
                sessions.append(record)
            }
        }

        sessions.sort { $0.lastActiveAt > $1.lastActiveAt }
        return Array(sessions.prefix(limit))
    }

    public func parseTranscriptFile(url: URL, conversationId: String) -> AISessionRecord? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        let modelName = "Gemini 2.5 Pro"
        var startedAt: Date = Date()
        var lastActiveAt: Date = Date.distantPast
        let projectName = "mac-tool-kit"
        var turns: [AITurnRecord] = []
        var totalToolCalls = 0

        var taskMap: [AITaskCategory: (count: Int, durationMs: Int64, input: Int64, output: Int64)] = [:]

        var totalInputTokens: Int64 = 0
        var totalOutputTokens: Int64 = 0
        var totalThinkingTokens: Int64 = 0

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        for (index, line) in lines.enumerated() {
            guard let jsonData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                continue
            }

            if let timeStr = obj["created_at"] as? String, let date = dateFormatter.date(from: timeStr) ?? ISO8601DateFormatter().date(from: timeStr) {
                if index == 0 { startedAt = date }
                if date > lastActiveAt { lastActiveAt = date }
            }

            var taskCat: AITaskCategory = .planning
            var taskDesc = "思考與規劃架構"

            if let toolCalls = obj["tool_calls"] as? [[String: Any]] {
                totalToolCalls += toolCalls.count
                for call in toolCalls {
                    let toolName = (call["name"] as? String) ?? "tool"
                    let args = (call["parameters"] as? [String: Any]) ?? (call["arguments"] as? [String: Any]) ?? [:]

                    if toolName.contains("run_command") {
                        let cmd = (args["CommandLine"] as? String) ?? ""
                        if cmd.contains("test") || cmd.contains("swift test") || cmd.contains("pytest") {
                            taskCat = .testing
                            taskDesc = "執行測試: \(cmd.prefix(35))"
                        } else {
                            taskCat = .bashCommand
                            taskDesc = "終端指令: \(cmd.prefix(35))"
                        }
                    } else if toolName.contains("replace_file_content") || toolName.contains("write_to_file") {
                        taskCat = .codeEdit
                        let file = (args["TargetFile"] as? String) ?? ""
                        taskDesc = "代碼修改: \(URL(fileURLWithPath: file).lastPathComponent)"
                    } else if toolName.contains("grep_search") || toolName.contains("find_by_name") || toolName.contains("view_file") {
                        taskCat = .codeSearch
                        taskDesc = "檢索代碼: \(toolName)"
                    } else {
                        taskCat = .other
                        taskDesc = "呼叫工具: \(toolName)"
                    }
                }
            }

            if let thinking = obj["thinking"] as? String, !thinking.isEmpty {
                let thinkTokens = Int64(thinking.count / 4)
                totalThinkingTokens += thinkTokens
            }

            // Estimate tokens per turn based on step payload length
            let approxInput = Int64(line.count / 8)
            let approxOutput = Int64(max(30, (obj["content"] as? String)?.count ?? 100) / 4)

            totalInputTokens += approxInput
            totalOutputTokens += approxOutput

            var current = taskMap[taskCat] ?? (count: 0, durationMs: 0, input: 0, output: 0)
            current.count += 1
            current.input += approxInput
            current.output += approxOutput
            taskMap[taskCat] = current

            let turnDate = (obj["created_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? startedAt
            turns.append(AITurnRecord(
                turnIndex: turns.count + 1,
                timestamp: turnDate,
                durationMs: 0,
                modelName: modelName,
                taskCategory: taskCat,
                taskDescription: taskDesc,
                inputTokens: approxInput,
                outputTokens: approxOutput,
                cacheReadTokens: 0,
                thinkingTokens: 0
            ))
        }

        if lastActiveAt == Date.distantPast {
            lastActiveAt = startedAt
        }

        let durationSec = max(1.0, lastActiveAt.timeIntervalSince(startedAt))
        let totalCost = pricing.calculateCostUSD(
            model: modelName,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheReadTokens: 0,
            thinkingTokens: totalThinkingTokens
        )

        let modelUsage = [AIModelUsage(
            modelName: modelName,
            turnCount: turns.count,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheReadTokens: 0,
            thinkingTokens: totalThinkingTokens,
            estimatedCostUSD: totalCost
        )]

        let totalTokens = max(1, totalInputTokens + totalOutputTokens)
        var taskBreakdown: [AITaskCategoryUsage] = []
        for (cat, stats) in taskMap {
            let share = Double(stats.input + stats.output) / Double(totalTokens)
            taskBreakdown.append(AITaskCategoryUsage(
                category: cat,
                callCount: stats.count,
                totalDurationMs: stats.durationMs,
                tokenShare: share,
                estimatedCostUSD: totalCost * share
            ))
        }
        taskBreakdown.sort { $0.callCount > $1.callCount }

        let tokenSummary = AITokenUsageSummary(
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            cacheReadTokens: 0,
            cacheWriteTokens: 0,
            thinkingTokens: totalThinkingTokens
        )

        return AISessionRecord(
            sessionId: conversationId,
            sessionShortId: String(conversationId.prefix(8)),
            toolType: .antigravity,
            projectName: projectName,
            projectPath: "\(NSHomeDirectory())/Documents/program/mac-tool-kit",
            gitBranch: "main",
            startedAt: startedAt,
            lastActiveAt: lastActiveAt,
            durationSeconds: durationSec,
            status: .active,
            totalTurns: turns.count,
            totalToolCalls: totalToolCalls,
            modelsUsed: modelUsage,
            taskBreakdown: taskBreakdown,
            tokenUsage: tokenSummary,
            estimatedCostUSD: totalCost,
            turns: turns
        )
    }
}
