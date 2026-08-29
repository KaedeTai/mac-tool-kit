import Foundation

public final class AISessionHistoryStore: @unchecked Sendable {
    private let storeURL: URL
    private let lock = NSLock()
    private var lastWriteErrorDescription: String?

    public init(storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.storeURL = base
                .appendingPathComponent("MacDashboard", isDirectory: true)
                .appendingPathComponent("ai-session-history.json")
        }
    }

    public func merge(current: [AISessionRecord]) -> [AISessionRecord] {
        lock.lock()
        defer { lock.unlock() }

        var records = Dictionary(uniqueKeysWithValues: load().map { record in
            let sanitized = sanitizeHistoricalRecord(record)
            return (sanitized.id, sanitized)
        })
        for session in current {
            if let previous = records[session.id] {
                records[session.id] = mergeEvidence(current: session, previous: previous)
            } else {
                records[session.id] = session
            }
        }
        let merged = records.values.sorted { $0.lastActiveAt > $1.lastActiveAt }
        // The in-memory result may retain ephemeral detail for the current UI,
        // but the permanent index stores only sanitized aggregate facts.
        persist(merged.map(sanitizeHistoricalRecord))
        return merged
    }

    public func persistenceStatus() -> AIDataProvenance {
        lock.lock()
        defer { lock.unlock() }
        if let lastWriteErrorDescription {
            return .unavailable("Permanent history write failed: \(lastWriteErrorDescription)")
        }
        return .measured("Application Support/MacDashboard/ai-session-history.json was written atomically")
    }

    private func load() -> [AISessionRecord] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([AISessionRecord].self, from: data)) ?? []
    }

    private func sanitizeHistoricalRecord(_ record: AISessionRecord) -> AISessionRecord {
        let trustedCost: AICostValue
        if record.cost.kind == .apiEquivalentEstimate {
            let source = record.cost.source.detail.lowercased()
            let hasOfficialRate = source.contains("official openai")
                || source.contains("official anthropic")
                || source.contains("official api list")
            let hasVersion = source.contains("captured \(AIPricingCalculator.rateCardDate)")
            let disclaimsBilling = source.contains("not billing")
                || source.contains("not provider billing")
            trustedCost = hasOfficialRate && hasVersion && disclaimsBilling
                ? record.cost
                : .unavailable(reason: "Stored estimate lacked a verifiable official rate-card source")
        } else {
            trustedCost = record.cost
        }
        return AISessionRecord(
            sessionId: record.sessionId,
            sessionShortId: record.sessionShortId,
            toolType: record.toolType,
            title: record.title,
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
            // A persisted snapshot is inactive until this refresh finds matching
            // provider runtime evidence. The runtime reconciler may override it.
            status: .completed,
            statusSource: .derived("Persistent history has no matching live provider evidence yet"),
            livePID: nil,
            liveCPU: nil,
            liveMemoryBytes: nil,
            totalTurns: record.totalTurns,
            totalToolCalls: record.totalToolCalls,
            modelsUsed: record.modelsUsed,
            taskBreakdown: record.taskBreakdown,
            tokenUsage: record.tokenUsage,
            cost: trustedCost,
            turns: []
        )
    }

    /// A fast metadata refresh may intentionally omit expensive historical
    /// token/model parsing. Do not let that absence erase evidence captured
    /// earlier from the same immutable provider session.
    private func mergeEvidence(current: AISessionRecord, previous: AISessionRecord) -> AISessionRecord {
        let currentTokensUnavailable: Bool
        if case .unavailable = current.tokenUsage.source {
            currentTokensUnavailable = true
        } else {
            currentTokensUnavailable = false
        }
        let currentCostUnavailable = current.cost.kind == .unavailable

        return AISessionRecord(
            sessionId: current.sessionId,
            sessionShortId: current.sessionShortId,
            toolType: current.toolType,
            title: current.title,
            projectName: current.projectName,
            parentProjectName: current.parentProjectName,
            projectPath: current.projectPath,
            gitBranch: current.gitBranch ?? previous.gitBranch,
            isSubagent: current.isSubagent,
            parentSessionId: current.parentSessionId ?? previous.parentSessionId,
            subagentSlug: current.subagentSlug ?? previous.subagentSlug,
            startedAt: min(current.startedAt, previous.startedAt),
            lastActiveAt: max(current.lastActiveAt, previous.lastActiveAt),
            durationSeconds: current.durationSeconds > 0 ? current.durationSeconds : previous.durationSeconds,
            status: current.status,
            statusSource: current.statusSource,
            livePID: current.livePID,
            liveCPU: current.liveCPU,
            liveMemoryBytes: current.liveMemoryBytes,
            totalTurns: max(current.totalTurns, previous.totalTurns),
            totalToolCalls: max(current.totalToolCalls, previous.totalToolCalls),
            modelsUsed: current.modelsUsed.isEmpty ? previous.modelsUsed : current.modelsUsed,
            taskBreakdown: current.taskBreakdown.isEmpty ? previous.taskBreakdown : current.taskBreakdown,
            tokenUsage: currentTokensUnavailable ? previous.tokenUsage : current.tokenUsage,
            cost: currentCostUnavailable ? previous.cost : current.cost,
            turns: current.turns
        )
    }

    private func persist(_ records: [AISessionRecord]) {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: storeURL, options: .atomic)
            lastWriteErrorDescription = nil
        } catch {
            // Live telemetry remains usable, but the UI must disclose that the
            // permanent history write failed.
            lastWriteErrorDescription = error.localizedDescription
        }
    }
}
