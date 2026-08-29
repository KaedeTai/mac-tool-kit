import Foundation
import Darwin

public struct StorageCategoryTarget: Sendable {
    public let id: String
    public let title: String
    public let paths: [URL]

    public init(id: String, title: String, paths: [URL]) {
        self.id = id
        self.title = title
        self.paths = paths
    }
}

public enum StorageCleanupImpact: Int, CaseIterable, Comparable, Sendable {
    case low = 0
    case medium = 1
    case high = 2

    public static func < (lhs: StorageCleanupImpact, rhs: StorageCleanupImpact) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .low: return "低影響"
        case .medium: return "中影響"
        case .high: return "高影響"
        }
    }
}

public struct StorageCleanupTarget: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let path: URL
    public let impact: StorageCleanupImpact
    public let consequence: String

    public init(
        id: String,
        title: String,
        path: URL,
        impact: StorageCleanupImpact,
        consequence: String
    ) {
        self.id = id
        self.title = title
        self.path = path
        self.impact = impact
        self.consequence = consequence
    }
}

public struct StorageCategorySnapshot: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let sourcePaths: [String]
    public let allocatedBytes: UInt64
    public let fileCount: Int
    public let isComplete: Bool
    public let notes: [String]
}

public struct StorageCleanupCandidate: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let path: String
    public let measuredBytes: UInt64
    public let impact: StorageCleanupImpact
    public let consequence: String
    public let isComplete: Bool
    public let isSelectable: Bool
    public let notes: [String]
}

public enum DockerDiskUsageKind: String, Sendable {
    case images
    case containers
    case volumes
    case buildCache
    case other
}

public struct DockerDiskUsageItem: Identifiable, Sendable {
    public var id: String { kind.rawValue }
    public let kind: DockerDiskUsageKind
    public let sourceType: String
    public let totalCount: Int
    public let activeCount: Int
    public let sizeBytes: UInt64
    public let reclaimableBytes: UInt64
    public let requiresExplicitVolumeDeletion: Bool
}

public struct DockerDiskUsageSummary: Sendable {
    public let items: [DockerDiskUsageItem]

    public var volumeReclaimableBytes: UInt64 {
        items.filter { $0.kind == .volumes }.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var nonVolumeReclaimableBytes: UInt64 {
        items.filter { $0.kind != .volumes }.reduce(0) { $0 + $1.reclaimableBytes }
    }
}

public struct StorageAnalysisSnapshot: Sendable {
    public let categories: [StorageCategorySnapshot]
    public let cleanupCandidates: [StorageCleanupCandidate]
    public let docker: DockerDiskUsageSummary?
    public let volumeTotalBytes: UInt64
    public let volumeAvailableBytes: UInt64
    public let scannedAt: Date

    public var volumeUsedBytes: UInt64 {
        volumeTotalBytes > volumeAvailableBytes ? volumeTotalBytes - volumeAvailableBytes : 0
    }

    public static let empty = StorageAnalysisSnapshot(
        categories: [],
        cleanupCandidates: [],
        docker: nil,
        volumeTotalBytes: 0,
        volumeAvailableBytes: 0,
        scannedAt: .distantPast
    )
}

public enum StorageCompositionMath {
    public static func unclassifiedUsedBytes(
        volumeUsedBytes: UInt64,
        measuredCategoryBytes: [UInt64]
    ) -> UInt64 {
        let measured = measuredCategoryBytes.reduce(UInt64(0)) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? UInt64.max : sum
        }
        return volumeUsedBytes > measured ? volumeUsedBytes - measured : 0
    }
}

public enum DockerDiskUsageParser {
    private struct Line: Decodable {
        let active: String?
        let reclaimable: String?
        let size: String?
        let totalCount: String?
        let type: String?

        enum CodingKeys: String, CodingKey {
            case active = "Active"
            case reclaimable = "Reclaimable"
            case size = "Size"
            case totalCount = "TotalCount"
            case type = "Type"
        }
    }

    public static func parse(_ report: String) -> DockerDiskUsageSummary? {
        let decoder = JSONDecoder()
        let items = report
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> DockerDiskUsageItem? in
                guard let data = String(line).data(using: .utf8),
                      let decoded = try? decoder.decode(Line.self, from: data),
                      let sourceType = decoded.type,
                      let sizeBytes = parseByteSize(decoded.size),
                      let reclaimableBytes = parseByteSize(decoded.reclaimable) else {
                    return nil
                }

                let kind: DockerDiskUsageKind
                switch sourceType.lowercased() {
                case "images": kind = .images
                case "containers": kind = .containers
                case "local volumes", "volumes": kind = .volumes
                case "build cache": kind = .buildCache
                default: kind = .other
                }

                return DockerDiskUsageItem(
                    kind: kind,
                    sourceType: sourceType,
                    totalCount: Int(decoded.totalCount ?? "") ?? 0,
                    activeCount: Int(decoded.active ?? "") ?? 0,
                    sizeBytes: sizeBytes,
                    reclaimableBytes: reclaimableBytes,
                    requiresExplicitVolumeDeletion: kind == .volumes
                )
            }

        return items.isEmpty ? nil : DockerDiskUsageSummary(items: items)
    }

    private static func parseByteSize(_ value: String?) -> UInt64? {
        guard let token = value?.split(separator: " ").first else { return nil }
        let text = String(token).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let units: [(suffix: String, multiplier: Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("kB", 1_000),
            ("KB", 1_000),
            ("B", 1)
        ]
        guard let unit = units.first(where: { text.hasSuffix($0.suffix) }) else { return nil }
        let numberText = String(text.dropLast(unit.suffix.count))
        guard let number = Double(numberText), number >= 0 else { return nil }
        let bytes = number * unit.multiplier
        guard bytes.isFinite, bytes <= Double(UInt64.max) else { return nil }
        return UInt64(bytes.rounded())
    }
}

public final class StorageAnalyzer: @unchecked Sendable {
    private final class ScanStopSignal: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }
    }

    private let categoryTargets: [StorageCategoryTarget]
    private let cleanupTargets: [StorageCleanupTarget]
    private let dockerReportProvider: @Sendable () -> String?
    private let fileManager: FileManager
    private let volumeReferenceURL: URL
    private let scanTimeLimitPerCategory: TimeInterval
    private let maximumConcurrentCategories: Int

    public init(
        categoryTargets: [StorageCategoryTarget],
        cleanupTargets: [StorageCleanupTarget],
        dockerReportProvider: @escaping @Sendable () -> String?,
        volumeReferenceURL: URL? = nil,
        scanTimeLimitPerCategory: TimeInterval = 3,
        maximumConcurrentCategories: Int = 4,
        fileManager: FileManager = .default
    ) {
        self.categoryTargets = categoryTargets
        self.cleanupTargets = cleanupTargets
        self.dockerReportProvider = dockerReportProvider
        self.fileManager = fileManager
        self.volumeReferenceURL = volumeReferenceURL
            ?? categoryTargets.first?.paths.first
            ?? fileManager.homeDirectoryForCurrentUser
        self.scanTimeLimitPerCategory = max(0, scanTimeLimitPerCategory)
        self.maximumConcurrentCategories = max(1, maximumConcurrentCategories)
    }

    public convenience init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        let categories = Self.defaultCategoryTargets(homeDirectory: homeDirectory)
        let cleanupTargets = Self.defaultCleanupTargets(homeDirectory: homeDirectory)
        self.init(
            categoryTargets: categories,
            cleanupTargets: cleanupTargets,
            dockerReportProvider: { Self.readDockerDiskUsage() },
            volumeReferenceURL: homeDirectory,
            maximumConcurrentCategories: max(categories.count, cleanupTargets.count)
        )
    }

    public func scan() -> StorageAnalysisSnapshot {
        let resultLock = NSLock()
        var indexedCategories: [Int: StorageCategorySnapshot] = [:]
        let categoryQueue = OperationQueue()
        categoryQueue.maxConcurrentOperationCount = maximumConcurrentCategories
        categoryQueue.qualityOfService = .utility
        let categoryGroup = DispatchGroup()
        let categoryStopSignal = ScanStopSignal()

        for (index, target) in categoryTargets.enumerated() {
            categoryGroup.enter()
            let operation = BlockOperation { [fileManager, scanTimeLimitPerCategory] in
                let deadline = Date().addingTimeInterval(scanTimeLimitPerCategory)
                let measurements = target.paths.map {
                    Self.measure(
                        path: $0,
                        fileManager: fileManager,
                        deadline: deadline,
                        shouldStop: { categoryStopSignal.isStopped }
                    )
                }
                let snapshot = StorageCategorySnapshot(
                    id: target.id,
                    title: target.title,
                    sourcePaths: target.paths.map(\.path),
                    allocatedBytes: measurements.reduce(0) { $0 + $1.allocatedBytes },
                    fileCount: measurements.reduce(0) { $0 + $1.fileCount },
                    isComplete: measurements.allSatisfy(\.isComplete),
                    notes: Array(measurements.flatMap(\.notes).prefix(8))
                )
                resultLock.lock()
                indexedCategories[index] = snapshot
                resultLock.unlock()
            }
            operation.completionBlock = { categoryGroup.leave() }
            categoryQueue.addOperation(operation)
        }
        let categoryWaveCount = Int(ceil(Double(categoryTargets.count) / Double(maximumConcurrentCategories)))
        let categoryWallClockLimit = max(1, Double(categoryWaveCount) * scanTimeLimitPerCategory + 1)
        if categoryGroup.wait(timeout: .now() + categoryWallClockLimit) == .timedOut {
            categoryStopSignal.stop()
            categoryQueue.cancelAllOperations()
        }
        let categories = categoryTargets.indices.map { index in
            resultLock.lock()
            let completed = indexedCategories[index]
            resultLock.unlock()
            if let completed { return completed }
            let target = categoryTargets[index]
            return StorageCategorySnapshot(
                id: target.id,
                title: target.title,
                sourcePaths: target.paths.map(\.path),
                allocatedBytes: 0,
                fileCount: 0,
                isComplete: false,
                notes: ["整體掃描達時間上限；此分類未完成，不以估算補值。"]
            )
        }

        var indexedCleanupCandidates: [Int: StorageCleanupCandidate] = [:]
        let cleanupQueue = OperationQueue()
        cleanupQueue.maxConcurrentOperationCount = maximumConcurrentCategories
        cleanupQueue.qualityOfService = .utility
        let cleanupGroup = DispatchGroup()
        let cleanupStopSignal = ScanStopSignal()
        for (index, target) in cleanupTargets.enumerated() {
            cleanupGroup.enter()
            let operation = BlockOperation { [fileManager] in
                let measurement = Self.measure(
                    path: target.path,
                    fileManager: fileManager,
                    deadline: Date().addingTimeInterval(2),
                    shouldStop: { cleanupStopSignal.isStopped }
                )
                let candidate = StorageCleanupCandidate(
                    id: target.id,
                    title: target.title,
                    path: target.path.path,
                    measuredBytes: measurement.allocatedBytes,
                    impact: target.impact,
                    consequence: target.consequence,
                    isComplete: measurement.isComplete,
                    isSelectable: measurement.exists && measurement.allocatedBytes > 0,
                    notes: measurement.notes
                )
                resultLock.lock()
                indexedCleanupCandidates[index] = candidate
                resultLock.unlock()
            }
            operation.completionBlock = { cleanupGroup.leave() }
            cleanupQueue.addOperation(operation)
        }
        let cleanupWaveCount = Int(ceil(Double(cleanupTargets.count) / Double(maximumConcurrentCategories)))
        let cleanupWallClockLimit = max(1, Double(cleanupWaveCount) * 2 + 1)
        if cleanupGroup.wait(timeout: .now() + cleanupWallClockLimit) == .timedOut {
            cleanupStopSignal.stop()
            cleanupQueue.cancelAllOperations()
        }
        let cleanupCandidates = cleanupTargets.indices.map { index in
            resultLock.lock()
            let completed = indexedCleanupCandidates[index]
            resultLock.unlock()
            if let completed { return completed }
            let target = cleanupTargets[index]
            return StorageCleanupCandidate(
                id: target.id,
                title: target.title,
                path: target.path.path,
                measuredBytes: 0,
                impact: target.impact,
                consequence: target.consequence,
                isComplete: false,
                isSelectable: false,
                notes: ["整體掃描達時間上限；此項目未完成，不提供清理。"]
            )
        }

        let volumeValues = try? volumeReferenceURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey
        ])
        let volumeTotalBytes = UInt64(max(0, volumeValues?.volumeTotalCapacity ?? 0))
        let volumeAvailableBytes = UInt64(max(0, volumeValues?.volumeAvailableCapacity ?? 0))

        return StorageAnalysisSnapshot(
            categories: categories,
            cleanupCandidates: cleanupCandidates,
            docker: dockerReportProvider().flatMap(DockerDiskUsageParser.parse),
            volumeTotalBytes: volumeTotalBytes,
            volumeAvailableBytes: volumeAvailableBytes,
            scannedAt: Date()
        )
    }

    public static func defaultCategoryTargets(homeDirectory: URL) -> [StorageCategoryTarget] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            StorageCategoryTarget(id: "documents", title: "文件", paths: [homeDirectory.appendingPathComponent("Documents", isDirectory: true)]),
            StorageCategoryTarget(id: "downloads", title: "下載項目", paths: [homeDirectory.appendingPathComponent("Downloads", isDirectory: true)]),
            StorageCategoryTarget(id: "desktop", title: "桌面", paths: [homeDirectory.appendingPathComponent("Desktop", isDirectory: true)]),
            StorageCategoryTarget(id: "media", title: "照片、影片與音樂", paths: [
                homeDirectory.appendingPathComponent("Pictures", isDirectory: true),
                homeDirectory.appendingPathComponent("Movies", isDirectory: true),
                homeDirectory.appendingPathComponent("Music", isDirectory: true)
            ]),
            StorageCategoryTarget(id: "applications", title: "使用者應用程式", paths: [homeDirectory.appendingPathComponent("Applications", isDirectory: true)]),
            StorageCategoryTarget(id: "application-data", title: "App 資料與容器", paths: [
                library.appendingPathComponent("Application Support", isDirectory: true),
                library.appendingPathComponent("Containers", isDirectory: true),
                library.appendingPathComponent("Group Containers", isDirectory: true)
            ]),
            StorageCategoryTarget(id: "developer", title: "開發工具資料", paths: [
                library.appendingPathComponent("Developer", isDirectory: true),
                homeDirectory.appendingPathComponent(".gradle", isDirectory: true),
                homeDirectory.appendingPathComponent(".npm", isDirectory: true),
                homeDirectory.appendingPathComponent(".cocoapods", isDirectory: true),
                homeDirectory.appendingPathComponent(".bun", isDirectory: true)
            ]),
            StorageCategoryTarget(id: "ai-tools", title: "AI 工具資料", paths: [
                homeDirectory.appendingPathComponent(".codex", isDirectory: true),
                homeDirectory.appendingPathComponent(".claude", isDirectory: true),
                homeDirectory.appendingPathComponent(".gemini", isDirectory: true),
                homeDirectory.appendingPathComponent(".antigravity", isDirectory: true)
            ]),
            StorageCategoryTarget(id: "caches", title: "使用者快取", paths: [library.appendingPathComponent("Caches", isDirectory: true)]),
            StorageCategoryTarget(id: "logs", title: "使用者日誌", paths: [library.appendingPathComponent("Logs", isDirectory: true)])
        ]
    }

    public static func defaultCleanupTargets(homeDirectory: URL) -> [StorageCleanupTarget] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        return [
            StorageCleanupTarget(
                id: "xcode-derived-data",
                title: "Xcode DerivedData",
                path: library.appendingPathComponent("Developer/Xcode/DerivedData", isDirectory: true),
                impact: .low,
                consequence: "只移除可重新建置的索引與編譯產物；下次 Xcode build 會較久。"
            ),
            StorageCleanupTarget(
                id: "homebrew-cache",
                title: "Homebrew 下載快取",
                path: library.appendingPathComponent("Caches/Homebrew", isDirectory: true),
                impact: .low,
                consequence: "已安裝套件不受影響；未來安裝可能重新下載。"
            ),
            StorageCleanupTarget(
                id: "npm-cache",
                title: "npm 套件快取",
                path: homeDirectory.appendingPathComponent(".npm/_cacache", isDirectory: true),
                impact: .low,
                consequence: "專案與 node_modules 不會刪除；下次安裝可能重新下載。"
            ),
            StorageCleanupTarget(
                id: "cocoapods-cache",
                title: "CocoaPods 快取",
                path: library.appendingPathComponent("Caches/CocoaPods", isDirectory: true),
                impact: .low,
                consequence: "Pod 專案不會刪除；下次安裝可能重新下載。"
            ),
            StorageCleanupTarget(
                id: "user-logs",
                title: "使用者日誌",
                path: library.appendingPathComponent("Logs", isDirectory: true),
                impact: .medium,
                consequence: "不影響 App 本體，但會失去部分除錯與歷史診斷紀錄。"
            ),
            StorageCleanupTarget(
                id: "trash",
                title: "垃圾桶",
                path: homeDirectory.appendingPathComponent(".Trash", isDirectory: true),
                impact: .high,
                consequence: "永久刪除垃圾桶內容，無法再從 Finder 還原；可能需要完整磁碟存取權限。"
            )
        ]
    }

    fileprivate struct PathMeasurement {
        let allocatedBytes: UInt64
        let fileCount: Int
        let exists: Bool
        let isComplete: Bool
        let notes: [String]
    }

    fileprivate static func measure(
        path: URL,
        fileManager: FileManager,
        deadline: Date? = nil,
        shouldStop: @Sendable () -> Bool = { false }
    ) -> PathMeasurement {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else {
            return PathMeasurement(
                allocatedBytes: 0,
                fileCount: 0,
                exists: false,
                isComplete: false,
                notes: ["路徑不存在：\(path.path)"]
            )
        }

        if shouldStop() || (deadline.map { Date() >= $0 } ?? false) {
            return PathMeasurement(
                allocatedBytes: 0,
                fileCount: 0,
                exists: true,
                isComplete: false,
                notes: ["掃描達時間上限：\(path.path)"]
            )
        }

        if !isDirectory.boolValue {
            guard let status = allocatedFileStatus(at: path), !status.isSymbolicLink else {
                return PathMeasurement(
                    allocatedBytes: 0,
                    fileCount: 0,
                    exists: true,
                    isComplete: false,
                    notes: ["無法讀取：\(path.path)"]
                )
            }
            return PathMeasurement(
                allocatedBytes: status.isRegularFile ? status.allocatedBytes : 0,
                fileCount: status.isRegularFile ? 1 : 0,
                exists: true,
                isComplete: true,
                notes: []
            )
        }

        var notes: [String] = []
        guard let enumerator = fileManager.enumerator(
            at: path,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { url, error in
                _ = error
                notes.append("無法讀取：\(url.path)（權限不足或檔案暫時無法存取）")
                return true
            }
        ) else {
            return PathMeasurement(
                allocatedBytes: 0,
                fileCount: 0,
                exists: true,
                isComplete: false,
                notes: ["無法掃描：\(path.path)"]
            )
        }

        var allocatedBytes: UInt64 = 0
        var fileCount = 0
        for case let fileURL as URL in enumerator {
            if shouldStop() || (deadline.map { Date() >= $0 } ?? false) {
                notes.append("掃描達時間上限：\(path.path)")
                break
            }
            guard let status = allocatedFileStatus(at: fileURL) else {
                notes.append("無法讀取：\(fileURL.path)（權限不足或檔案暫時無法存取）")
                continue
            }
            if status.isSymbolicLink {
                enumerator.skipDescendants()
                continue
            }
            guard status.isRegularFile else { continue }
            let (sum, overflow) = allocatedBytes.addingReportingOverflow(status.allocatedBytes)
            allocatedBytes = overflow ? UInt64.max : sum
            fileCount += 1
        }

        return PathMeasurement(
            allocatedBytes: allocatedBytes,
            fileCount: fileCount,
            exists: true,
            isComplete: notes.isEmpty,
            notes: Array(notes.prefix(8))
        )
    }

    private static func allocatedFileStatus(
        at url: URL
    ) -> (allocatedBytes: UInt64, isRegularFile: Bool, isSymbolicLink: Bool)? {
        var info = stat()
        let result = url.withUnsafeFileSystemRepresentation { pathPointer in
            guard let pathPointer else { return Int32(-1) }
            return lstat(pathPointer, &info)
        }
        guard result == 0 else { return nil }

        let fileType = info.st_mode & mode_t(S_IFMT)
        let blocks = max(Int64(0), Int64(info.st_blocks))
        return (
            allocatedBytes: UInt64(blocks) * 512,
            isRegularFile: fileType == mode_t(S_IFREG),
            isSymbolicLink: fileType == mode_t(S_IFLNK)
        )
    }

    private static func readDockerDiskUsage() -> String? {
        let binaries = [
            "/usr/local/bin/docker",
            "/opt/homebrew/bin/docker",
            "/usr/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker"
        ]
        guard let executable = binaries.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["system", "df", "--format", "{{json .}}"]
        process.standardOutput = output
        process.standardError = Pipe()
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        if finished.wait(timeout: .now() + 3) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}

public struct StorageCleanupItemResult: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let succeeded: Bool
    public let measuredBytesBefore: UInt64
    public let measuredBytesAfter: UInt64
    public let errors: [String]
}

public struct StorageCleanupResult: Sendable {
    public let items: [StorageCleanupItemResult]
    public let rejectedIDs: [String]
    public let volumeFreeBytesBefore: UInt64?
    public let volumeFreeBytesAfter: UInt64?

    public var measuredItemDecreaseBytes: UInt64 {
        items.reduce(0) { total, item in
            let decrease = item.measuredBytesBefore > item.measuredBytesAfter
                ? item.measuredBytesBefore - item.measuredBytesAfter
                : 0
            let (sum, overflow) = total.addingReportingOverflow(decrease)
            return overflow ? UInt64.max : sum
        }
    }

    public var volumeFreeIncreaseBytes: UInt64? {
        guard let before = volumeFreeBytesBefore, let after = volumeFreeBytesAfter else { return nil }
        return after > before ? after - before : 0
    }
}

public final class StorageCleanupService: @unchecked Sendable {
    private let targetsByID: [String: StorageCleanupTarget]
    private let fileManager: FileManager

    public init(
        targets: [StorageCleanupTarget] = StorageAnalyzer.defaultCleanupTargets(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ),
        fileManager: FileManager = .default
    ) {
        self.targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        self.fileManager = fileManager
    }

    public func clean(candidateIDs: Set<String>) -> StorageCleanupResult {
        let selectedTargets = candidateIDs.compactMap { targetsByID[$0] }
        let rejected = candidateIDs.filter { targetsByID[$0] == nil }.sorted()
        let freeBefore = selectedTargets.first.flatMap { volumeAvailableBytes(for: $0.path) }

        let items = selectedTargets.sorted { $0.id < $1.id }.map { target in
            let before = StorageAnalyzer.measure(path: target.path, fileManager: fileManager)
            var errors: [String] = []

            if before.exists {
                do {
                    let children = try fileManager.contentsOfDirectory(
                        at: target.path,
                        includingPropertiesForKeys: nil,
                        options: []
                    )
                    for child in children {
                        do {
                            try fileManager.removeItem(at: child)
                        } catch {
                            errors.append("\(child.lastPathComponent)：\(error.localizedDescription)")
                        }
                    }
                } catch {
                    errors.append(error.localizedDescription)
                }
            } else {
                errors.append("路徑不存在")
            }

            let after = StorageAnalyzer.measure(path: target.path, fileManager: fileManager)
            return StorageCleanupItemResult(
                id: target.id,
                title: target.title,
                succeeded: errors.isEmpty,
                measuredBytesBefore: before.allocatedBytes,
                measuredBytesAfter: after.allocatedBytes,
                errors: Array(errors.prefix(8))
            )
        }

        let freeAfter = selectedTargets.first.flatMap { volumeAvailableBytes(for: $0.path) }
        return StorageCleanupResult(
            items: items,
            rejectedIDs: rejected,
            volumeFreeBytesBefore: freeBefore,
            volumeFreeBytesAfter: freeAfter
        )
    }

    private func volumeAvailableBytes(for path: URL) -> UInt64? {
        let existingPath: URL
        if fileManager.fileExists(atPath: path.path) {
            existingPath = path
        } else {
            existingPath = path.deletingLastPathComponent()
        }
        guard let values = try? existingPath.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let capacity = values.volumeAvailableCapacity,
              capacity >= 0 else {
            return nil
        }
        return UInt64(capacity)
    }
}
