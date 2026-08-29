import Foundation

/// Persistent metadata cache for immutable provider transcript files.
///
/// Only parsed session metadata is retained; raw transcript text and turn-level
/// command content are intentionally excluded by the parsers.
public final class AITelemetryFileCache: @unchecked Sendable {
    private struct Entry: Codable {
        let modificationTimeInterval: TimeInterval
        let fileSize: Int
        let record: AISessionRecord
    }

    private let storeURL: URL
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var isDirty = false

    public init(name: String, directory: URL? = nil) {
        let baseDirectory = directory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("MacDashboard", isDirectory: true)
        self.storeURL = baseDirectory.appendingPathComponent(name)
        self.entries = Self.load(from: storeURL)
    }

    public func record(path: String, modificationDate: Date, fileSize: Int) -> AISessionRecord? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[path],
              entry.modificationTimeInterval == modificationDate.timeIntervalSince1970,
              entry.fileSize == fileSize else { return nil }
        return entry.record
    }

    public func store(
        record: AISessionRecord,
        path: String,
        modificationDate: Date,
        fileSize: Int
    ) {
        lock.lock()
        entries[path] = Entry(
            modificationTimeInterval: modificationDate.timeIntervalSince1970,
            fileSize: fileSize,
            record: record
        )
        isDirty = true
        lock.unlock()
    }

    public func flush() {
        lock.lock()
        guard isDirty else {
            lock.unlock()
            return
        }
        let snapshot = entries
        isDirty = false
        lock.unlock()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storeURL, options: .atomic)
        } catch {
            lock.lock()
            isDirty = true
            lock.unlock()
        }
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: Entry].self, from: data)) ?? [:]
    }
}
