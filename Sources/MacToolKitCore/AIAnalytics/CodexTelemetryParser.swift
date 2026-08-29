import Foundation

public final class CodexTelemetryParser: @unchecked Sendable {
    public static let shared = CodexTelemetryParser()

    private let pricing = AIPricingCalculator.shared
    private let codexDirectory: URL
    private let persistentCache: AITelemetryFileCache?
    private let cacheLock = NSLock()
    private var cache: [String: (modified: Date, size: Int, record: AISessionRecord)] = [:]

    public init(codexDirectory: URL? = nil) {
        let usesDefaultDirectory = codexDirectory == nil
        self.codexDirectory = codexDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex", isDirectory: true)
        self.persistentCache = usesDefaultDirectory
            ? AITelemetryFileCache(name: "codex-telemetry-cache-v5.json")
            : nil
    }

    public func parseAllSessions(limit: Int? = nil) -> [AISessionRecord] {
        let titles = loadTitles()
        let sessionsDirectory = codexDirectory.appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [(URL, Date)] = []
        for case let file as URL in enumerator where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true else { continue }
            files.append((file, values?.contentModificationDate ?? .distantPast))
        }
        files.sort { $0.1 > $1.1 }

        var records: [AISessionRecord] = []
        let selectedFiles = limit.map { Array(files.prefix($0)) } ?? files
        for (file, modified) in selectedFiles {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let indexedTitle = Self.indexedTitle(for: file, titles: titles)
            let record: AISessionRecord?
            cacheLock.lock()
            let cached = cache[file.path]
            cacheLock.unlock()
            if cached?.modified == modified, cached?.size == size {
                record = cached?.record
            } else if let persisted = persistentCache?.record(
                path: file.path,
                modificationDate: modified,
                fileSize: size
            ) {
                record = persisted
            } else {
                record = parseSessionFile(
                    url: file,
                    title: indexedTitle,
                    scanCompleteModelHistory: Date().timeIntervalSince(modified) <= 24 * 60 * 60
                )
                if let record {
                    cacheLock.lock()
                    cache[file.path] = (modified, size, record)
                    cacheLock.unlock()
                    persistentCache?.store(
                        record: record,
                        path: file.path,
                        modificationDate: modified,
                        fileSize: size
                    )
                }
            }
            if let record {
                records.append(replacingTitle(
                    of: record,
                    with: titles[record.sessionId] ?? indexedTitle
                ))
            }
        }
        persistentCache?.flush()
        return records.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    public func parseSessionFile(
        url: URL,
        title: String?,
        scanCompleteModelHistory: Bool = true
    ) -> AISessionRecord? {
        guard let content = Self.readBoundedLog(url) else { return nil }

        var sessionID: String?
        var parentSessionID: String?
        var cwd: String?
        var startedAt: Date?
        var lastActiveAt: Date?
        var modelNames = Set<String>()
        var subagentSlug: String?
        var gitBranch: String?
        var totalTurns = 0
        var totalToolCalls = 0
        var latestUsage: AITokenUsageSummary?

        for line in content.split(whereSeparator: { $0.isNewline }) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            if let timestamp = Self.parseDate(object["timestamp"] as? String) {
                if startedAt == nil || timestamp < startedAt! { startedAt = timestamp }
                if lastActiveAt == nil || timestamp > lastActiveAt! { lastActiveAt = timestamp }
            }

            let type = object["type"] as? String
            guard let payload = object["payload"] as? [String: Any] else { continue }

            switch type {
            case "session_meta":
                sessionID = (payload["id"] as? String) ?? (payload["session_id"] as? String)
                parentSessionID = payload["parent_thread_id"] as? String
                cwd = payload["cwd"] as? String
                if let timestamp = Self.parseDate(payload["timestamp"] as? String) {
                    startedAt = timestamp
                }
                if let source = payload["source"] as? [String: Any] {
                    subagentSlug = source["subagent"] as? String
                }
                if let git = payload["git"] as? [String: Any] {
                    gitBranch = git["branch"] as? String
                }
            case "turn_context":
                totalTurns += 1
                if let turnCWD = payload["cwd"] as? String, !turnCWD.isEmpty {
                    // A Codex task can move from a generic startup directory to
                    // the actual project. The latest provider-reported cwd is
                    // the factual grouping key for the current task.
                    cwd = turnCWD
                }
                if let model = payload["model"] as? String, !model.isEmpty {
                    modelNames.insert(model)
                }
            case "response_item":
                if let payloadType = payload["type"] as? String,
                   payloadType == "function_call" || payloadType == "custom_tool_call" {
                    totalToolCalls += 1
                }
            case "event_msg":
                guard payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let usage = info["total_token_usage"] as? [String: Any] else { break }
                latestUsage = AITokenUsageSummary(
                    inputTokens: Self.int64(usage["input_tokens"]),
                    outputTokens: Self.int64(usage["output_tokens"]),
                    cacheReadTokens: Self.int64(usage["cached_input_tokens"]),
                    cacheWriteTokens: Self.int64(usage["cache_write_input_tokens"]),
                    thinkingTokens: Self.int64(usage["reasoning_output_tokens"]),
                    providerTotalTokens: Self.int64(usage["total_tokens"]),
                    source: .providerReported("Codex rollout token_count.total_token_usage")
                )
            default:
                break
            }
        }

        let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let boundedReadWasComplete = fileSize <= Self.boundedReadByteCount
        if scanCompleteModelHistory && !boundedReadWasComplete {
            let facts = Self.scanTurnContextFacts(in: url)
            modelNames = facts.models
            if let latestCWD = facts.latestCWD { cwd = latestCWD }
        } else if !boundedReadWasComplete {
            // A head/tail sample cannot prove that the cumulative usage belongs
            // to one model, even when both samples happen to show the same ID.
            modelNames.removeAll()
        }

        if let migratedThreadID = Self.migratedThreadID(from: url) {
            // One Codex migration format keeps the original session_meta ID in
            // the log while appending the canonical thread ID to the filename.
            // thread_history_1.sqlite keys runtime state by that appended ID.
            sessionID = migratedThreadID
        }

        guard let sessionID, let rawCWD = cwd else { return nil }
        let projectPath = Self.normalizedProjectPath(rawCWD)
        let pathName = URL(fileURLWithPath: projectPath).lastPathComponent
        let projectName = pathName.isEmpty ? projectPath : pathName
        let firstDate = startedAt ?? lastActiveAt ?? .distantPast
        let lastDate = lastActiveAt ?? firstDate
        let tokenUsage = latestUsage ?? .unavailable
        let exactModelName = modelNames.count == 1 ? modelNames.first : nil
        let estimate: Double?
        if let exactModelName, latestUsage != nil {
            estimate = pricing.calculateCostUSD(
                model: exactModelName,
                inputTokens: tokenUsage.inputTokens,
                outputTokens: tokenUsage.outputTokens,
                cacheReadTokens: tokenUsage.cacheReadTokens,
                cacheWriteTokens: tokenUsage.cacheWriteTokens,
                thinkingTokens: tokenUsage.thinkingTokens
            )
        } else {
            estimate = nil
        }
        let modelUsage: [AIModelUsage]
        if let modelName = exactModelName, latestUsage != nil {
            modelUsage = [AIModelUsage(
                modelName: modelName,
                turnCount: totalTurns,
                inputTokens: tokenUsage.inputTokens,
                outputTokens: tokenUsage.outputTokens,
                cacheReadTokens: tokenUsage.cacheReadTokens,
                thinkingTokens: tokenUsage.thinkingTokens,
                estimatedCostUSD: estimate ?? 0
            )]
        } else {
            modelUsage = []
        }

        return AISessionRecord(
            sessionId: sessionID,
            toolType: .codex,
            title: title ?? "Codex \(String(sessionID.prefix(8)))",
            projectName: projectName,
            parentProjectName: projectName,
            projectPath: projectPath,
            gitBranch: gitBranch,
            isSubagent: parentSessionID != nil || subagentSlug != nil,
            parentSessionId: parentSessionID,
            subagentSlug: subagentSlug,
            startedAt: firstDate,
            lastActiveAt: lastDate,
            durationSeconds: 0,
            status: .unknown,
            statusSource: .unavailable("Codex rollout files contain activity, not an authoritative live task state"),
            totalTurns: totalTurns,
            totalToolCalls: totalToolCalls,
            modelsUsed: modelUsage,
            taskBreakdown: [],
            tokenUsage: tokenUsage,
            cost: estimate.map {
                AICostValue.apiEquivalentEstimate(
                    $0,
                    source: pricing.sourceDescription(for: exactModelName ?? "")
                        ?? "Official standard token rates captured \(AIPricingCalculator.rateCardDate); API-equivalent estimate, not billing"
                )
            } ?? .unavailable(reason: codexEstimateUnavailableReason(
                hasUsage: latestUsage != nil,
                modelNames: modelNames
            )),
            turns: []
        )
    }

    private func codexEstimateUnavailableReason(hasUsage: Bool, modelNames: Set<String>) -> String {
        if !hasUsage { return "API-equivalent estimate unavailable: Codex rollout has no token_count usage" }
        if modelNames.isEmpty { return "API-equivalent estimate unavailable: Codex rollout did not identify a model" }
        if modelNames.count > 1 { return "API-equivalent estimate unavailable: cumulative tokens span multiple models" }
        return "API-equivalent estimate unavailable: no exact official rate for \(modelNames.first ?? "unknown model")"
    }

    private func loadTitles() -> [String: String] {
        let index = codexDirectory.appendingPathComponent("session_index.jsonl")
        guard let data = try? Data(contentsOf: index),
              let content = String(data: data, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in content.split(whereSeparator: { $0.isNewline }) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let title = object["thread_name"] as? String,
                  !title.isEmpty else { continue }
            result[id] = title
        }
        return result
    }

    private func replacingTitle(of record: AISessionRecord, with title: String?) -> AISessionRecord {
        guard let title, !title.isEmpty else { return record }
        return AISessionRecord(
            sessionId: record.sessionId,
            sessionShortId: record.sessionShortId,
            toolType: record.toolType,
            title: title,
            projectName: record.projectName,
            parentProjectName: record.parentProjectName,
            projectPath: record.projectPath,
            gitBranch: record.gitBranch,
            isSubagent: record.isSubagent,
            parentSessionId: record.parentSessionId,
            subagentSlug: record.subagentSlug,
            startedAt: record.startedAt,
            lastActiveAt: record.lastActiveAt,
            durationSeconds: record.durationSeconds,
            status: record.status,
            statusSource: record.statusSource,
            livePID: record.livePID,
            liveCPU: record.liveCPU,
            liveMemoryBytes: record.liveMemoryBytes,
            totalTurns: record.totalTurns,
            totalToolCalls: record.totalToolCalls,
            modelsUsed: record.modelsUsed,
            taskBreakdown: record.taskBreakdown,
            tokenUsage: record.tokenUsage,
            cost: record.cost,
            turns: record.turns
        )
    }

    private static func indexedTitle(for url: URL, titles: [String: String]) -> String? {
        for id in filenameThreadIDs(from: url) {
            if let title = titles[id], !title.isEmpty { return title }
        }
        return nil
    }

    private static func migratedThreadID(from url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.contains("_"),
              let candidate = name.split(separator: "_").last.map(String.init),
              UUID(uuidString: candidate) != nil else { return nil }
        return candidate.lowercased()
    }

    private static func filenameThreadIDs(from url: URL) -> [String] {
        let name = url.deletingPathExtension().lastPathComponent
        var result: [String] = []
        if let migrated = migratedThreadID(from: url) { result.append(migrated) }
        let prefix = name.split(separator: "_").first.map(String.init) ?? name
        let rootCandidate = String(prefix.suffix(36)).lowercased()
        if UUID(uuidString: rootCandidate) != nil, !result.contains(rootCandidate) {
            result.append(rootCandidate)
        }
        return result
    }

    private static func normalizedProjectPath(_ path: String) -> String {
        for marker in ["/.claude/worktrees/", "/.codex/worktrees/"] {
            if let range = path.range(of: marker) {
                return String(path[..<range.lowerBound])
            }
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let integer = value as? Int64 { return integer }
        if let integer = value as? Int { return Int64(integer) }
        return 0
    }

    private static func readBoundedLog(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        let headLimit: UInt64 = 64 * 1024
        let tailLimit: UInt64 = 256 * 1024
        if size <= headLimit + tailLimit {
            try? handle.seek(toOffset: 0)
            guard let data = try? handle.readToEnd() else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: Int(headLimit))) ?? Data()
        try? handle.seek(toOffset: size - tailLimit)
        let tail = (try? handle.readToEnd()) ?? Data()
        guard let headText = String(data: head, encoding: .utf8),
              let tailText = String(data: tail, encoding: .utf8) else { return nil }
        return headText + "\n" + tailText
    }

    private static let boundedReadByteCount = Int(64 * 1024 + 256 * 1024)

    private struct TurnContextFacts {
        var models = Set<String>()
        var latestCWD: String?
    }

    /// Scans only for turn_context model identifiers and cwd values. This is deliberately a
    /// byte-level pass so large response/tool payloads are never decoded or
    /// retained in memory merely to prove one-model attribution.
    private static func scanTurnContextFacts(in url: URL) -> TurnContextFacts {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return TurnContextFacts() }
        defer { try? handle.close() }

        let turnMarker = Data(#""type":"turn_context""#.utf8)
        let modelMarker = Data(#""model":""#.utf8)
        let cwdMarker = Data(#""cwd":""#.utf8)
        let quote = UInt8(ascii: "\"")
        let chunkSize = 1 * 1024 * 1024
        let overlapSize = 64 * 1024
        var overlap = Data()
        var facts = TurnContextFacts()

        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            var window = overlap
            window.append(chunk)
            var searchStart = window.startIndex
            while searchStart < window.endIndex,
                  let turnRange = window.range(
                    of: turnMarker,
                    options: [],
                    in: searchStart..<window.endIndex
                  ) {
                let contextEnd = min(window.endIndex, turnRange.upperBound + overlapSize)
                if let modelRange = window.range(
                    of: modelMarker,
                    options: [],
                    in: turnRange.upperBound..<contextEnd
                ),
                   let closingQuote = window[modelRange.upperBound..<contextEnd].firstIndex(of: quote),
                   let model = String(
                    data: window[modelRange.upperBound..<closingQuote],
                    encoding: .utf8
                   ),
                   !model.isEmpty {
                    facts.models.insert(model)
                }
                if let cwdRange = window.range(
                    of: cwdMarker,
                    options: [],
                    in: turnRange.upperBound..<contextEnd
                ),
                   let closingQuote = window[cwdRange.upperBound..<contextEnd].firstIndex(of: quote),
                   let latestCWD = String(
                    data: window[cwdRange.upperBound..<closingQuote],
                    encoding: .utf8
                   ),
                   !latestCWD.isEmpty {
                    facts.latestCWD = latestCWD
                }
                searchStart = turnRange.upperBound
            }
            overlap = Data(window.suffix(overlapSize))
        }

        return facts
    }
}
