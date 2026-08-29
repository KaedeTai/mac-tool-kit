import XCTest
@testable import MacToolKitCore

final class StorageManagementTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDashboardStorageTests-(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testAnalyzerMeasuresOnlyNamedTargetsAndDisclosesMissingPaths() throws {
        let root = try temporaryDirectory()
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 8_192)
            .write(to: documents.appendingPathComponent("fixture.bin"))

        let analyzer = StorageAnalyzer(
            categoryTargets: [
                StorageCategoryTarget(id: "documents", title: "文件", paths: [documents]),
                StorageCategoryTarget(
                    id: "downloads",
                    title: "下載",
                    paths: [root.appendingPathComponent("Missing", isDirectory: true)]
                )
            ],
            cleanupTargets: [],
            dockerReportProvider: { nil }
        )

        let snapshot = analyzer.scan()
        let measured = try XCTUnwrap(snapshot.categories.first { $0.id == "documents" })
        let missing = try XCTUnwrap(snapshot.categories.first { $0.id == "downloads" })

        XCTAssertGreaterThanOrEqual(measured.allocatedBytes, 8_192)
        XCTAssertEqual(measured.fileCount, 1)
        XCTAssertTrue(measured.isComplete)
        XCTAssertEqual(missing.allocatedBytes, 0)
        XCTAssertFalse(missing.isComplete)
        XCTAssertTrue(missing.notes.contains(where: { $0.contains("不存在") }))
        XCTAssertGreaterThan(snapshot.volumeTotalBytes, 0)
        XCTAssertLessThanOrEqual(snapshot.volumeAvailableBytes, snapshot.volumeTotalBytes)
    }

    func testUnclassifiedUsedBytesNeverBecomesNegative() {
        XCTAssertEqual(
            StorageCompositionMath.unclassifiedUsedBytes(
                volumeUsedBytes: 100,
                measuredCategoryBytes: [60, 30]
            ),
            10
        )
        XCTAssertEqual(
            StorageCompositionMath.unclassifiedUsedBytes(
                volumeUsedBytes: 100,
                measuredCategoryBytes: [80, 40]
            ),
            0
        )
    }

    func testAnalyzerStopsAtConfiguredCategoryTimeLimitAndMarksResultPartial() throws {
        let root = try temporaryDirectory()
        for index in 0..<20 {
            try Data(repeating: UInt8(index), count: 1_024)
                .write(to: root.appendingPathComponent("file-\(index).bin"))
        }
        let analyzer = StorageAnalyzer(
            categoryTargets: [StorageCategoryTarget(id: "bounded", title: "Bounded", paths: [root])],
            cleanupTargets: [],
            dockerReportProvider: { nil },
            scanTimeLimitPerCategory: 0
        )

        let snapshot = analyzer.scan()
        let category = try XCTUnwrap(snapshot.categories.first)

        XCTAssertFalse(category.isComplete)
        XCTAssertLessThan(category.fileCount, 20)
        XCTAssertTrue(category.notes.contains(where: { $0.contains("時間上限") }))
    }

    func testDockerDiskUsageParserKeepsVolumesSeparateFromOrdinaryReclaim() throws {
        let report = """
        {"Active":"15","Reclaimable":"34.75GB (63%)","Size":"54.94GB","TotalCount":"92","Type":"Images"}
        {"Active":"12","Reclaimable":"2.272GB (97%)","Size":"2.335GB","TotalCount":"17","Type":"Containers"}
        {"Active":"11","Reclaimable":"5.739GB (59%)","Size":"9.612GB","TotalCount":"77","Type":"Local Volumes"}
        {"Active":"21","Reclaimable":"18.54GB","Size":"40GB","TotalCount":"363","Type":"Build Cache"}
        """

        let summary = try XCTUnwrap(DockerDiskUsageParser.parse(report))
        XCTAssertEqual(summary.items.count, 4)
        XCTAssertEqual(summary.volumeReclaimableBytes, 5_739_000_000)
        XCTAssertEqual(
            summary.nonVolumeReclaimableBytes,
            34_750_000_000 + 2_272_000_000 + 18_540_000_000
        )
        XCTAssertTrue(summary.items.first { $0.kind == .volumes }?.requiresExplicitVolumeDeletion == true)
    }

    func testCleanupDeletesOnlyConfiguredTargetContentsAndRejectsUnknownIDs() throws {
        let root = try temporaryDirectory()
        let allowed = root.appendingPathComponent("Allowed", isDirectory: true)
        let protected = root.appendingPathComponent("Protected", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: protected, withIntermediateDirectories: true)
        try Data(repeating: 0xCD, count: 4_096).write(to: allowed.appendingPathComponent("cache.bin"))
        try Data(repeating: 0xEF, count: 4_096).write(to: protected.appendingPathComponent("keep.bin"))

        let service = StorageCleanupService(targets: [
            StorageCleanupTarget(
                id: "allowed-cache",
                title: "測試快取",
                path: allowed,
                impact: .low,
                consequence: "可重新建立"
            )
        ])

        let result = service.clean(candidateIDs: ["allowed-cache", "../../Protected"])

        XCTAssertEqual(result.rejectedIDs, ["../../Protected"])
        XCTAssertTrue(result.items.first { $0.id == "allowed-cache" }?.succeeded == true)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: allowed.path), [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: protected.appendingPathComponent("keep.bin").path))
        XCTAssertGreaterThan(result.items.first?.measuredBytesBefore ?? 0, 0)
        XCTAssertEqual(result.items.first?.measuredBytesAfter, 0)
    }

    func testCleanupWithNoSelectionChangesNothing() throws {
        let root = try temporaryDirectory()
        let allowed = root.appendingPathComponent("Allowed", isDirectory: true)
        try FileManager.default.createDirectory(at: allowed, withIntermediateDirectories: true)
        let file = allowed.appendingPathComponent("cache.bin")
        try Data(repeating: 0xAA, count: 4_096).write(to: file)
        let service = StorageCleanupService(targets: [
            StorageCleanupTarget(
                id: "allowed-cache",
                title: "測試快取",
                path: allowed,
                impact: .low,
                consequence: "可重新建立"
            )
        ])

        let result = service.clean(candidateIDs: [])

        XCTAssertTrue(result.items.isEmpty)
        XCTAssertTrue(result.rejectedIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
