import Foundation

public final class AntigravityTelemetryParser: @unchecked Sendable {
    public static let shared = AntigravityTelemetryParser()
    private let brainDirectory: URL
    private let persistentCache: AITelemetryFileCache?

    public init(brainDirectory: URL? = nil) {
        let usesDefaultDirectory = brainDirectory == nil
        self.brainDirectory = brainDirectory
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".gemini/antigravity/brain", isDirectory: true)
        self.persistentCache = usesDefaultDirectory
            ? AITelemetryFileCache(name: "antigravity-telemetry-cache.json")
            : nil
    }

    public func parseAllSessions(limit: Int? = nil) -> [AISessionRecord] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: brainDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let records = folders.compactMap { folder -> AISessionRecord? in
            let transcript = folder.appendingPathComponent(".system_generated/logs/transcript.jsonl")
            guard let values = try? transcript.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                  values.isRegularFile == true else { return nil }
            let modified = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            if let record = persistentCache?.record(
                path: transcript.path,
                modificationDate: modified,
                fileSize: size
            ) {
                return record
            }
            guard let record = parseTranscriptFile(url: transcript, conversationId: folder.lastPathComponent) else {
                return nil
            }
            persistentCache?.store(
                record: record,
                path: transcript.path,
                modificationDate: modified,
                fileSize: size
            )
            return record
        }.sorted { $0.lastActiveAt > $1.lastActiveAt }
        persistentCache?.flush()
        return limit.map { Array(records.prefix($0)) } ?? records
    }

    public func parseTranscriptFile(url: URL, conversationId: String) -> AISessionRecord? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else { return nil }

        var startedAt: Date?
        var lastActiveAt: Date?
        var toolCallCount = 0
        for line in content.split(whereSeparator: { $0.isNewline }) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let date = Self.parseDate(object["created_at"] as? String) {
                if startedAt == nil || date < startedAt! { startedAt = date }
                if lastActiveAt == nil || date > lastActiveAt! { lastActiveAt = date }
            }
            toolCallCount += (object["tool_calls"] as? [[String: Any]])?.count ?? 0
        }

        guard let first = startedAt ?? lastActiveAt else { return nil }
        let last = lastActiveAt ?? first
        return AISessionRecord(
            sessionId: conversationId,
            toolType: .antigravity,
            title: "Antigravity \(String(conversationId.prefix(8)))",
            projectName: "Unlinked Antigravity",
            parentProjectName: "Unlinked Antigravity",
            projectPath: "",
            startedAt: first,
            lastActiveAt: last,
            durationSeconds: 0,
            status: .unknown,
            statusSource: .unavailable("Antigravity transcript does not expose an authoritative live state"),
            totalTurns: 0,
            totalToolCalls: toolCallCount,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable,
            turns: []
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
