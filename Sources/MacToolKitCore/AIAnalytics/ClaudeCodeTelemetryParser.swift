import Foundation

public final class ClaudeCodeTelemetryParser: Sendable {
    public static let shared = ClaudeCodeTelemetryParser()
    private let pricing = AIPricingCalculator.shared

    public init() {}

    public func parseAllSessions(limit: Int = 40) -> [AISessionRecord] {
        let homeDir = NSHomeDirectory()
        let claudeProjectsDir = URL(fileURLWithPath: "\(homeDir)/.claude/projects")

        let fileManager = FileManager.default
        guard let projectFolders = try? fileManager.contentsOfDirectory(
            at: claudeProjectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var allSessionFiles: [(url: URL, modDate: Date)] = []

        for folder in projectFolders {
            guard let isDir = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory, isDir else {
                continue
            }

            guard let files = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for file in files where file.pathExtension == "jsonl" {
                let modDate = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                allSessionFiles.append((url: file, modDate: modDate))
            }
        }

        // Sort by most recent
        allSessionFiles.sort { $0.modDate > $1.modDate }

        var sessions: [AISessionRecord] = []
        for item in allSessionFiles.prefix(limit * 2) {
            if let record = parseSessionFile(url: item.url) {
                sessions.append(record)
                if sessions.count >= limit {
                    break
                }
            }
        }

        return sessions
    }

    public func parseSessionFile(url: URL) -> AISessionRecord? {
        let sessionId = url.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            return nil
        }

        let lines = content.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty else { return nil }

        var firstCwd: String? = nil
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

            // Extract session metadata from initial line
            if firstCwd == nil, let cwd = obj["cwd"] as? String, !cwd.isEmpty, cwd != "/" {
                firstCwd = cwd
            }
            if gitBranch == nil, let branch = obj["gitBranch"] as? String, !branch.isEmpty {
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

                var currentModel = modelMap[model] ?? (turns: 0, input: 0, output: 0, cacheRead: 0, thinking: 0)
                currentModel.turns += 1
                currentModel.input += inTokens
                currentModel.output += outTokens
                currentModel.cacheRead += cacheRead
                currentModel.thinking += thinking
                modelMap[model] = currentModel

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
                    durationMs: 2500,
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

        guard totalInputTokens + totalOutputTokens + totalCacheReadTokens > 0 else {
            return nil
        }

        // Aggregate models
        var modelsUsed: [AIModelUsage] = []
        var totalCost: Double = 0.0

        for (mName, usage) in modelMap {
            let cost = pricing.calculateCostUSD(
                model: mName,
                inputTokens: usage.input,
                outputTokens: usage.output,
                cacheReadTokens: usage.cacheRead,
                cacheWriteTokens: 0,
                thinkingTokens: usage.thinking
            )
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

        let durationSec: TimeInterval = totalDurationMs > 0 ? Double(totalDurationMs) / 1000.0 : max(1.0, lastActiveAt.timeIntervalSince(startedAt))

        let folderName = url.deletingLastPathComponent().lastPathComponent
        let identity = resolveProjectIdentity(folderName: folderName, firstCwd: firstCwd)

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
            projectName: identity.projectName,
            parentProjectName: identity.parentProjectName,
            projectPath: identity.projectPath,
            gitBranch: gitBranch,
            isSubagent: identity.isSubagent,
            subagentSlug: identity.subagentSlug,
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

    private func resolveProjectIdentity(folderName: String, firstCwd: String?) -> (projectName: String, parentProjectName: String, isSubagent: Bool, subagentSlug: String?, projectPath: String) {
        let fileManager = FileManager.default

        // 1. Worktree folder format (e.g. -Users-peterting-Documents-artogo-aeo-dashboard--claude-worktrees-quizzical-kowalevski-b2c78d)
        if folderName.contains("--claude-worktrees-") {
            let parts = folderName.components(separatedBy: "--claude-worktrees-")
            let parentFolder = parts[0]
            let slug = parts.count > 1 ? parts[1] : "worktree-subagent"
            let parentResolved = resolveProjectIdentity(folderName: parentFolder, firstCwd: firstCwd)
            return (projectName: "🌿 Subagent (\(slug))", parentProjectName: parentResolved.parentProjectName, isSubagent: true, subagentSlug: slug, projectPath: parentResolved.projectPath)
        }

        // 2. Subagent runner format (e.g. -Users-peterting--claude-double-shot-latte)
        if folderName.contains("--claude-") {
            let parts = folderName.components(separatedBy: "--claude-")
            let slug = parts.count > 1 ? parts[1] : "subagent"
            if let cwd = firstCwd, !cwd.isEmpty, cwd != "/", cwd != NSHomeDirectory() {
                var cleanCwd = cwd
                if cleanCwd.contains("/.claude/worktrees/") {
                    cleanCwd = cleanCwd.components(separatedBy: "/.claude/worktrees/")[0]
                }
                let pName = URL(fileURLWithPath: cleanCwd).lastPathComponent
                return (projectName: "🌿 Subagent (\(slug))", parentProjectName: pName.isEmpty ? "Workspace" : pName, isSubagent: true, subagentSlug: slug, projectPath: cleanCwd)
            }
            return (projectName: "🌿 Subagent (\(slug))", parentProjectName: "Claude Subagent", isSubagent: true, subagentSlug: slug, projectPath: "\(NSHomeDirectory())/.claude")
        }

        // 3. Search exact filesystem path
        let cleanFolder = folderName.hasPrefix("-") ? String(folderName.dropFirst()) : folderName

        let baseDirs = [
            "/Users/peterting/Documents/program",
            "/Users/peterting/Documents/artogo",
            "/Users/peterting/Documents/Cowork/AI顧問服務",
            "/Users/peterting/Documents",
            "/Users/peterting"
        ]

        for base in baseDirs {
            let baseEncoded = String(base.replacingOccurrences(of: "/", with: "-").dropFirst())
            if cleanFolder.hasPrefix(baseEncoded + "-") {
                let remainder = String(cleanFolder.dropFirst(baseEncoded.count + 1))

                let candidatePath = "\(base)/\(remainder)"
                if fileManager.fileExists(atPath: candidatePath) {
                    return (projectName: "👑 主 Session (\(remainder))", parentProjectName: remainder, isSubagent: false, subagentSlug: nil, projectPath: candidatePath)
                }

                if let children = try? fileManager.contentsOfDirectory(atPath: base) {
                    for child in children where !child.hasPrefix(".") {
                        if remainder == child {
                            let fullPath = "\(base)/\(child)"
                            return (projectName: "👑 主 Session (\(child))", parentProjectName: child, isSubagent: false, subagentSlug: nil, projectPath: fullPath)
                        } else if remainder.hasPrefix(child + "-") {
                            let subSlug = String(remainder.dropFirst(child.count + 1))
                            let fullPath = "\(base)/\(child)"
                            return (projectName: "🌿 Subagent (\(subSlug))", parentProjectName: child, isSubagent: true, subagentSlug: subSlug, projectPath: fullPath)
                        }
                    }
                }
            }
        }

        let pName = cleanFolder.components(separatedBy: "-").last ?? "Workspace"
        return (projectName: "👑 主 Session (\(pName))", parentProjectName: pName, isSubagent: false, subagentSlug: nil, projectPath: "/Users/peterting/\(pName)")
    }
}
