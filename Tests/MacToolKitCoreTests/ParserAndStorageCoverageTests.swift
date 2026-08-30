import XCTest
import SQLite3
@testable import MacToolKitCore
@testable import MacToolKitHardwareABI

final class ParserAndStorageCoverageTests: XCTestCase {
    private func temporaryDirectory(_ name: String = UUID().uuidString) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDashboardCoverage-\(name)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeJSONLines(_ objects: [[String: Any]], to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lines = try objects.map { object -> String in
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return try XCTUnwrap(String(data: data, encoding: .utf8))
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    private func record(id: String, cost: AICostValue = .unavailable, turns: [AITurnRecord] = []) -> AISessionRecord {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        return AISessionRecord(
            sessionId: id,
            toolType: .codex,
            projectName: "project",
            projectPath: "/tmp/project",
            gitBranch: "main",
            startedAt: date,
            lastActiveAt: date.addingTimeInterval(10),
            durationSeconds: 10,
            status: .active,
            livePID: 123,
            liveCPU: 10,
            liveMemoryBytes: 20,
            totalTurns: 1,
            totalToolCalls: 1,
            modelsUsed: [AIModelUsage(modelName: "gpt-5.6-sol", turnCount: 1, inputTokens: 10, outputTokens: 2, cacheReadTokens: 1, thinkingTokens: 0, estimatedCostUSD: 0.001)],
            taskBreakdown: [AITaskCategoryUsage(category: .testing, callCount: 1, totalDurationMs: 10, tokenShare: 1, estimatedCostUSD: 0.001)],
            tokenUsage: AITokenUsageSummary(inputTokens: 10, outputTokens: 2, providerTotalTokens: 12),
            cost: cost,
            turns: turns
        )
    }

    func testAntigravityParserHandlesDirectoryLimitInvalidLinesAndBothDateFormats() throws {
        let root = try temporaryDirectory("antigravity")
        let transcript = root
            .appendingPathComponent("conversation-123", isDirectory: true)
            .appendingPathComponent(".system_generated/logs/transcript.jsonl")
        try writeJSONLines([
            ["created_at": "2030-03-17T17:46:40.123Z", "tool_calls": [["name": "a"], ["name": "b"]]],
            ["created_at": "2030-03-17T17:47:40Z", "tool_calls": [["name": "c"]]],
            ["created_at": NSNull(), "tool_calls": []]
        ], to: transcript)
        let invalid = root
            .appendingPathComponent("invalid", isDirectory: true)
            .appendingPathComponent(".system_generated/logs/transcript.jsonl")
        try FileManager.default.createDirectory(at: invalid.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json\n".utf8).write(to: invalid)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("missing"), withIntermediateDirectories: true)

        let parser = AntigravityTelemetryParser(brainDirectory: root)
        let records = parser.parseAllSessions()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].sessionId, "conversation-123")
        XCTAssertEqual(records[0].totalToolCalls, 3)
        XCTAssertEqual(records[0].toolType, .antigravity)
        XCTAssertEqual(parser.parseAllSessions(limit: 0).count, 0)
        XCTAssertNil(parser.parseTranscriptFile(url: root.appendingPathComponent("missing.jsonl"), conversationId: "missing"))
        XCTAssertNil(parser.parseTranscriptFile(url: invalid, conversationId: "invalid"))
        XCTAssertTrue(AntigravityTelemetryParser(brainDirectory: root.appendingPathComponent("absent")).parseAllSessions().isEmpty)
    }

    func testClaudeParserAggregatesEveryToolCategoryCacheBucketAndSidechainIdentity() throws {
        let root = try temporaryDirectory("claude-full")
        let projectDir = root.appendingPathComponent("-Users-test-project", isDirectory: true)
        let file = projectDir.appendingPathComponent("agent-child-123.jsonl")
        let tools: [(String, [String: Any])] = [
            ("bash", ["command": "swift test"]),
            ("terminal", ["CommandLine": "git status"]),
            ("run_command", ["command": "ls"]),
            ("fileedit", ["file_path": "/tmp/a.swift"]),
            ("edit", ["TargetFile": "/tmp/b.swift"]),
            ("replace_file_content", ["file_path": "/tmp/c.swift"]),
            ("write_to_file", ["file_path": "/tmp/d.swift"]),
            ("grep", [:]), ("grep_search", [:]), ("find_by_name", [:]),
            ("view_file", [:]), ("view", [:]),
            ("websearch", [:]), ("read_url_content", [:]),
            ("mystery", [:])
        ]
        var objects: [[String: Any]] = [[
            "cwd": "/tmp/project/.claude/worktrees/w1",
            "sessionId": "parent-session",
            "agentId": "child-session",
            "isSidechain": true,
            "customTitle": "Child title",
            "gitBranch": "feature",
            "timestamp": "2030-03-17T17:46:40.123Z",
            "subtype": "turn_duration",
            "durationMs": Int64(2_500)
        ]]
        for (index, tool) in tools.enumerated() {
            objects.append([
                "timestamp": "2030-03-17T17:47:\(String(format: "%02d", index % 60)).123Z",
                "message": [
                    "model": "claude-sonnet-4-6",
                    "usage": [
                        "input_tokens": NSNumber(value: 10),
                        "output_tokens": NSNumber(value: 2),
                        "cache_read_input_tokens": NSNumber(value: 3),
                        "cache_creation_input_tokens": NSNumber(value: 5),
                        "cache_creation": [
                            "ephemeral_5m_input_tokens": NSNumber(value: 2),
                            "ephemeral_1h_input_tokens": NSNumber(value: 3)
                        ],
                        "output_tokens_details": ["thinking_tokens": NSNumber(value: index == 0 ? 1 : 0)]
                    ],
                    "content": [["type": "tool_use", "name": tool.0, "input": tool.1]]
                ]
            ])
        }
        objects.append([
            "timestamp": "2030-03-17T17:48:00Z",
            "summary": "Summary wins last",
            "message": [
                "model": "claude-sonnet-4-6",
                "usage": ["input_tokens": 0, "output_tokens": 0],
                "content": [["type": "thinking"]]
            ]
        ])
        try writeJSONLines(objects, to: file)

        let parser = ClaudeCodeTelemetryParser(projectsDirectory: root)
        let parsed = try XCTUnwrap(parser.parseSessionFile(url: file))
        XCTAssertTrue(parsed.isSubagent)
        XCTAssertEqual(parsed.sessionId, "child-session")
        XCTAssertEqual(parsed.parentSessionId, "parent-session")
        XCTAssertEqual(parsed.projectPath, "/tmp/project")
        XCTAssertEqual(parsed.projectName, "project")
        XCTAssertEqual(parsed.title, "Summary wins last")
        XCTAssertEqual(parsed.gitBranch, "feature")
        XCTAssertEqual(parsed.durationSeconds, 2.5)
        XCTAssertEqual(parsed.totalToolCalls, tools.count)
        XCTAssertEqual(parsed.modelsUsed.first?.turnCount, tools.count)
        XCTAssertEqual(parsed.cost.kind, .apiEquivalentEstimate)
        XCTAssertTrue(Set(parsed.taskBreakdown.map(\.category)).isSuperset(of: [.testing, .bashCommand, .codeEdit, .codeSearch, .web, .other, .planning]))
        XCTAssertTrue(parsed.turns.isEmpty)

        let firstScan = parser.parseAllSessions()
        let secondScan = parser.parseAllSessions(limit: 1)
        XCTAssertEqual(firstScan.count, 1)
        XCTAssertEqual(secondScan.count, 1)
    }

    func testClaudeParserFailsClosedForUnknownPriceUnclassifiedCacheAndMissingUsage() throws {
        let root = try temporaryDirectory("claude-failclosed")
        let parser = ClaudeCodeTelemetryParser(projectsDirectory: root)
        let unknown = root.appendingPathComponent("unknown.jsonl")
        try writeJSONLines([["cwd": "/tmp/p", "sessionId": "u", "timestamp": "2030-03-17T17:46:40Z", "slug": "Slug", "message": [
            "model": "unknown-model",
            "usage": ["input_tokens": 1, "output_tokens": 1, "cache_creation_input_tokens": 3],
            "content": []
        ]]], to: unknown)
        XCTAssertEqual(parser.parseSessionFile(url: unknown)?.cost.kind, .unavailable)

        let noUsage = root.appendingPathComponent("no-usage.jsonl")
        try writeJSONLines([["cwd": NSHomeDirectory() + "/.claude/runtime", "timestamp": "2030-03-17T17:46:40Z", "message": ["model": "claude-sonnet-4-6", "content": []]]], to: noUsage)
        let noUsageRecord = try XCTUnwrap(parser.parseSessionFile(url: noUsage))
        XCTAssertEqual(noUsageRecord.cost.kind, .unavailable)
        XCTAssertTrue(noUsageRecord.isActivityOnlyRecord)
        XCTAssertEqual(noUsageRecord.projectName, "Unlinked Claude Runtime")
        XCTAssertEqual(noUsageRecord.projectPath, "")

        let noCWD = root.appendingPathComponent("no-cwd.jsonl")
        try writeJSONLines([["timestamp": "2030-03-17T17:46:40Z"]], to: noCWD)
        XCTAssertEqual(parser.parseSessionFile(url: noCWD)?.projectName, "Unlinked Claude Metadata")
        let empty = root.appendingPathComponent("empty.jsonl")
        try Data().write(to: empty)
        XCTAssertNil(parser.parseSessionFile(url: empty))
        XCTAssertNil(parser.parseSessionFile(url: root.appendingPathComponent("absent.jsonl")))
    }

    func testClaudeOldMetadataUsesBoundedHeadTailAndSubagentFolderIdentity() throws {
        let root = try temporaryDirectory("claude-old")
        let file = root
            .appendingPathComponent("-Users-test-project/subagents", isDirectory: true)
            .appendingPathComponent("agent-oldchild.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let head = #"{"cwd":"/tmp/old-project","sessionId":"main-old","agentId":"oldchild","isSidechain":true,"gitBranch":"old","timestamp":"2029-01-01T00:00:00.000Z","customTitle":"Old child"}"#
        let tail = #"{"timestamp":"2029-01-01T00:01:00Z","summary":"Tail title"}"#
        var data = Data(head.utf8)
        data.append(Data(repeating: 0x20, count: 140_000))
        data.append(Data("\n".utf8))
        data.append(Data(tail.utf8))
        try data.write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10_000)], ofItemAtPath: file.path)

        let parser = ClaudeCodeTelemetryParser(projectsDirectory: root)
        let record = try XCTUnwrap(parser.parseAllSessions().first)
        XCTAssertTrue(record.isSubagent)
        XCTAssertEqual(record.sessionId, "oldchild")
        XCTAssertEqual(record.parentSessionId, "main-old")
        XCTAssertEqual(record.projectName, "old-project")
        XCTAssertEqual(record.title, "Tail title")
        XCTAssertEqual(record.modelsUsed, [])
        XCTAssertEqual(record.tokenUsage.source.label, "不可取得")
    }

    func testHistoryStoreCoversInvalidLoadEvidenceMergeAndWriteFailure() throws {
        let root = try temporaryDirectory("history")
        let storeURL = root.appendingPathComponent("history.json")
        try Data("not-json".utf8).write(to: storeURL)
        let store = AISessionHistoryStore(storeURL: storeURL)
        let turn = AITurnRecord(turnIndex: 1, timestamp: Date(), durationMs: 1, modelName: nil, taskCategory: .other, taskDescription: "secret")
        let untrusted = record(id: "same", cost: .apiEquivalentEstimate(1, source: "local guess"), turns: [turn])
        _ = store.merge(current: [untrusted])
        XCTAssertEqual(store.persistenceStatus().label, "實測")

        let refresh = AISessionRecord(
            sessionId: "same",
            toolType: .codex,
            title: "new title",
            projectName: "project",
            projectPath: "/tmp/project",
            startedAt: Date(timeIntervalSince1970: 1_900_000_100),
            lastActiveAt: Date(timeIntervalSince1970: 1_900_000_005),
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        let merged = try XCTUnwrap(store.merge(current: [refresh]).first)
        XCTAssertEqual(merged.modelsUsed.first?.modelName, "gpt-5.6-sol")
        XCTAssertEqual(merged.tokenUsage.totalTokens, 12)
        XCTAssertEqual(merged.cost.kind, .unavailable)
        XCTAssertEqual(merged.durationSeconds, 10)
        XCTAssertEqual(merged.totalTurns, 1)

        let blockingFile = root.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blockingFile)
        let failing = AISessionHistoryStore(storeURL: blockingFile.appendingPathComponent("history.json"))
        _ = failing.merge(current: [record(id: "failure")])
        XCTAssertEqual(failing.persistenceStatus().label, "不可取得")
    }

    func testTelemetryCacheCoversLoadHitMissFlushAndRetryAfterWriteFailure() throws {
        let root = try temporaryDirectory("cache")
        let cache = AITelemetryFileCache(name: "cache.json", directory: root)
        let date = Date(timeIntervalSince1970: 123)
        let value = record(id: "cache")
        XCTAssertNil(cache.record(path: "p", modificationDate: date, fileSize: 1))
        cache.flush()
        cache.store(record: value, path: "p", modificationDate: date, fileSize: 1)
        XCTAssertEqual(cache.record(path: "p", modificationDate: date, fileSize: 1)?.sessionId, "cache")
        XCTAssertNil(cache.record(path: "p", modificationDate: date.addingTimeInterval(1), fileSize: 1))
        XCTAssertNil(cache.record(path: "p", modificationDate: date, fileSize: 2))
        cache.flush()
        let reloaded = AITelemetryFileCache(name: "cache.json", directory: root)
        XCTAssertEqual(reloaded.record(path: "p", modificationDate: date, fileSize: 1)?.sessionId, "cache")

        let blockingFile = root.appendingPathComponent("file")
        try Data("x".utf8).write(to: blockingFile)
        let failing = AITelemetryFileCache(name: "cache.json", directory: blockingFile)
        failing.store(record: value, path: "p", modificationDate: date, fileSize: 1)
        failing.flush()
        failing.flush()
    }

    func testStorageValueTypesDefaultsParserAndOverflowMath() throws {
        XCTAssertTrue(StorageCleanupImpact.low < .medium)
        XCTAssertTrue(StorageCleanupImpact.medium < .high)
        XCTAssertEqual(StorageCleanupImpact.allCases.map(\.title), ["低影響", "中影響", "高影響"])
        let root = try temporaryDirectory("storage-defaults")
        let categories = StorageAnalyzer.defaultCategoryTargets(homeDirectory: root)
        let cleanup = StorageAnalyzer.defaultCleanupTargets(homeDirectory: root)
        XCTAssertEqual(categories.count, 10)
        XCTAssertEqual(cleanup.count, 6)
        XCTAssertEqual(cleanup.map(\.impact), [.low, .low, .low, .low, .medium, .high])

        let report = """
        {"Active":"x","Reclaimable":"1TB (1%)","Size":"1TB","TotalCount":"x","Type":"Other"}
        {"Active":"2","Reclaimable":"2MB","Size":"2MB","TotalCount":"3","Type":"Volumes"}
        {"Active":"1","Reclaimable":"4kB","Size":"5KB","TotalCount":"6","Type":"Containers"}
        {"Active":"1","Reclaimable":"7B","Size":"8B","TotalCount":"9","Type":"Images"}
        invalid
        {"Active":"1","Reclaimable":"-1GB","Size":"1GB","TotalCount":"1","Type":"Images"}
        {"Active":"1","Reclaimable":"NaNGB","Size":"1GB","TotalCount":"1","Type":"Images"}
        {"Active":"1","Reclaimable":"1XB","Size":"1GB","TotalCount":"1","Type":"Images"}
        """
        let docker = try XCTUnwrap(DockerDiskUsageParser.parse(report))
        XCTAssertEqual(docker.items.count, 4)
        XCTAssertEqual(docker.items[0].id, DockerDiskUsageKind.other.rawValue)
        XCTAssertEqual(docker.items[0].activeCount, 0)
        XCTAssertEqual(docker.items[0].totalCount, 0)
        XCTAssertNil(DockerDiskUsageParser.parse("invalid\n{}"))

        XCTAssertEqual(StorageCompositionMath.unclassifiedUsedBytes(volumeUsedBytes: 10, measuredCategoryBytes: [UInt64.max, 1]), 0)
        XCTAssertEqual(StorageAnalysisSnapshot.empty.volumeUsedBytes, 0)
        let snapshot = StorageAnalysisSnapshot(categories: [], cleanupCandidates: [], docker: nil, volumeTotalBytes: 100, volumeAvailableBytes: 40, scannedAt: Date())
        XCTAssertEqual(snapshot.volumeUsedBytes, 60)
        let reversed = StorageAnalysisSnapshot(categories: [], cleanupCandidates: [], docker: nil, volumeTotalBytes: 40, volumeAvailableBytes: 100, scannedAt: Date())
        XCTAssertEqual(reversed.volumeUsedBytes, 0)

        let results = StorageCleanupResult(
            items: [
                StorageCleanupItemResult(id: "a", title: "a", succeeded: true, measuredBytesBefore: UInt64.max, measuredBytesAfter: 0, errors: []),
                StorageCleanupItemResult(id: "b", title: "b", succeeded: true, measuredBytesBefore: 1, measuredBytesAfter: 0, errors: []),
                StorageCleanupItemResult(id: "c", title: "c", succeeded: true, measuredBytesBefore: 0, measuredBytesAfter: 1, errors: [])
            ],
            rejectedIDs: [],
            volumeFreeBytesBefore: 10,
            volumeFreeBytesAfter: 20
        )
        XCTAssertEqual(results.measuredItemDecreaseBytes, UInt64.max)
        XCTAssertEqual(results.volumeFreeIncreaseBytes, 10)
        XCTAssertEqual(StorageCleanupResult(items: [], rejectedIDs: [], volumeFreeBytesBefore: nil, volumeFreeBytesAfter: 1).volumeFreeIncreaseBytes, nil)
        XCTAssertEqual(StorageCleanupResult(items: [], rejectedIDs: [], volumeFreeBytesBefore: 20, volumeFreeBytesAfter: 10).volumeFreeIncreaseBytes, 0)
    }

    func testCodexParserCachesFileAndCapturesGitToolsWorktreeAndUnknownRate() throws {
        let root = try temporaryDirectory("codex-cache")
        let sessions = root.appendingPathComponent("sessions/2026/08/30", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-08-30T01:00:00.000Z","type":"session_meta","payload":{"id":"codex-cache","cwd":"/tmp/project/.codex/worktrees/task","git":{"branch":"codex/coverage"}}}"#,
            #"{"timestamp":"2026-08-30T01:00:01.000Z","type":"turn_context","payload":{"model":"unpriced-provider-model"}}"#,
            #"{"timestamp":"2026-08-30T01:00:02.000Z","type":"response_item","payload":{"type":"function_call"}}"#,
            #"{"timestamp":"2026-08-30T01:00:03.000Z","type":"response_item","payload":{"type":"custom_tool_call"}}"#,
            #"{"timestamp":"2026-08-30T01:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":20,"output_tokens":4,"total_tokens":24}}}}"#
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let parser = CodexTelemetryParser(codexDirectory: root)
        let first = try XCTUnwrap(parser.parseAllSessions().first)
        let cached = try XCTUnwrap(parser.parseAllSessions().first)
        XCTAssertEqual(first.gitBranch, "codex/coverage")
        XCTAssertEqual(first.totalToolCalls, 2)
        XCTAssertEqual(first.projectPath, "/tmp/project")
        XCTAssertEqual(first.cost.kind, .unavailable)
        XCTAssertTrue(first.cost.source.detail.contains("no exact official rate"))
        XCTAssertEqual(cached.sessionId, first.sessionId)
    }

    func testStorageAnalyzerScansFilesSymlinksCleanupCandidatesAndDocker() throws {
        let root = try temporaryDirectory("storage-scan")
        let directory = root.appendingPathComponent("directory", isDirectory: true)
        let cleanupDirectory = root.appendingPathComponent("cleanup", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cleanupDirectory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("file.bin")
        try Data(repeating: 1, count: 4_096).write(to: file)
        try Data(repeating: 2, count: 4_096).write(to: cleanupDirectory.appendingPathComponent("cache.bin"))
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link"), withDestinationURL: file)

        let analyzer = StorageAnalyzer(
            categoryTargets: [
                StorageCategoryTarget(id: "dir", title: "Dir", paths: [directory]),
                StorageCategoryTarget(id: "file", title: "File", paths: [file])
            ],
            cleanupTargets: [
                StorageCleanupTarget(id: "cleanup", title: "Cleanup", path: cleanupDirectory, impact: .low, consequence: "fixture"),
                StorageCleanupTarget(id: "missing", title: "Missing", path: root.appendingPathComponent("missing"), impact: .high, consequence: "fixture")
            ],
            dockerReportProvider: { "{\"Active\":\"0\",\"Reclaimable\":\"1GB\",\"Size\":\"2GB\",\"TotalCount\":\"1\",\"Type\":\"Build Cache\"}" },
            volumeReferenceURL: root,
            maximumConcurrentCategories: 1
        )
        let snapshot = analyzer.scan()
        XCTAssertEqual(snapshot.categories.count, 2)
        XCTAssertEqual(snapshot.categories.first { $0.id == "dir" }?.fileCount, 1)
        XCTAssertEqual(snapshot.categories.first { $0.id == "file" }?.fileCount, 1)
        XCTAssertTrue(snapshot.cleanupCandidates.first { $0.id == "cleanup" }?.isSelectable == true)
        XCTAssertTrue(snapshot.cleanupCandidates.first { $0.id == "missing" }?.isSelectable == false)
        XCTAssertEqual(snapshot.docker?.items.first?.kind, .buildCache)
        XCTAssertGreaterThan(snapshot.volumeTotalBytes, 0)
    }

    func testDefaultStorageAnalyzerUsesMeasuredTemporaryHomeLayout() throws {
        let root = try temporaryDirectory("storage-default-analyzer")
        let documents = root.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 2_048).write(to: documents.appendingPathComponent("document.bin"))

        let snapshot = StorageAnalyzer(homeDirectory: root).scan()
        XCTAssertEqual(snapshot.categories.count, 10)
        XCTAssertEqual(snapshot.cleanupCandidates.count, 6)
        XCTAssertEqual(snapshot.categories.first { $0.id == "documents" }?.fileCount, 1)
        XCTAssertTrue(snapshot.categories.first { $0.id == "documents" }?.isComplete == true)
    }

    func testStorageCleanupReportsMissingAndNonDirectoryFailuresWithoutDeletingOutsideScope() throws {
        let root = try temporaryDirectory("storage-clean")
        let missing = root.appendingPathComponent("missing")
        let file = root.appendingPathComponent("file.bin")
        try Data(repeating: 1, count: 4_096).write(to: file)
        let service = StorageCleanupService(targets: [
            StorageCleanupTarget(id: "missing", title: "Missing", path: missing, impact: .low, consequence: "fixture"),
            StorageCleanupTarget(id: "file", title: "File", path: file, impact: .low, consequence: "fixture")
        ])
        let result = service.clean(candidateIDs: ["missing", "file", "unknown"])
        XCTAssertEqual(result.rejectedIDs, ["unknown"])
        XCTAssertEqual(result.items.count, 2)
        XCTAssertTrue(result.items.allSatisfy { !$0.succeeded })
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testFanProtocolAndHardwareABICoverValidAndHostileInputs() throws {
        XCTAssertFalse(FanWriteOutcome.allSucceeded([]))
        XCTAssertFalse(FanWriteOutcome.allSucceeded([true, false]))
        XCTAssertTrue(FanWriteOutcome.allSucceeded([true, true]))
        XCTAssertEqual(FanHelperSocketTrust.evaluate(mode: 0o100660, ownerUID: 0, groupGID: 80), .unsafe("Helper endpoint is not a UNIX socket"))
        XCTAssertEqual(FanHelperSocketTrust.evaluate(mode: 0o140660, ownerUID: 1, groupGID: 80), .unsafe("Socket owner must be root"))
        XCTAssertEqual(FanHelperSocketTrust.evaluate(mode: 0o140660, ownerUID: 0, groupGID: 1), .unsafe("Socket group must be admin"))
        XCTAssertEqual(FanHelperSocketTrust.evaluate(mode: 0o140666, ownerUID: 0, groupGID: 80), .unsafe("Socket permissions must be exactly 0660"))
        XCTAssertEqual(FanHelperSocketTrust.evaluate(mode: 0o140660, ownerUID: 0, groupGID: 80), .trusted)

        XCTAssertEqual(FanHelperCapability.unreachable.localizedDescription, "讀回助手未連線")
        XCTAssertEqual(FanHelperCapability.reachableWithoutReadback.localizedDescription, "讀回助手已啟動，但無法取得風扇硬體資料")
        XCTAssertTrue(FanHelperCapability.ready(fanCount: 2).hasVerifiedFanReadback)
        XCTAssertFalse(FanHelperCapability.unreachable.hasVerifiedFanReadback)
        XCTAssertTrue(FanHelperCapability.ready(fanCount: 2).localizedDescription.contains("2"))
        XCTAssertEqual(FanHelperProtocolParser.capability(pingSucceeded: false, fanResponse: nil), .unreachable)
        XCTAssertEqual(FanHelperProtocolParser.capability(pingSucceeded: true, fanResponse: nil), .reachableWithoutReadback)

        let response: [String: Any] = ["success": true, "fans": [
            ["index": NSNumber(value: 1), "actualRPM": NSNumber(value: 2_000), "minRPM": NSNumber(value: 1_000), "maxRPM": NSNumber(value: 4_000), "targetRPM": NSNumber(value: 2_500), "isManual": true, "name": "\u{0000} Fan B "],
            ["index": NSNumber(value: 0), "actualRPM": NSNumber(value: 1_500), "minRPM": NSNumber(value: 1_000), "maxRPM": NSNumber(value: 4_000), "targetRPM": NSNumber(value: 0), "isManual": false]
        ]]
        let fans = try XCTUnwrap(FanHelperProtocolParser.fanStatuses(from: response, currentMode: .balanced()))
        XCTAssertEqual(fans.map(\.fanIndex), [0, 1])
        XCTAssertEqual(fans[0].name, "風扇 1")
        XCTAssertEqual(fans[0].mode, .automatic)
        XCTAssertEqual(fans[1].mode, .balanced())
        XCTAssertEqual(FanHelperProtocolParser.capability(pingSucceeded: true, fanResponse: response), .ready(fanCount: 2))

        let invalidFans: [[[String: Any]]] = [
            [],
            [["index": true, "actualRPM": 1, "minRPM": 1, "maxRPM": 2, "targetRPM": 1, "isManual": false]],
            [["index": 0.5, "actualRPM": 1, "minRPM": 1, "maxRPM": 2, "targetRPM": 1, "isManual": false]],
            [["index": 16, "actualRPM": 1, "minRPM": 1, "maxRPM": 2, "targetRPM": 1, "isManual": false]],
            [["index": 0, "actualRPM": -1, "minRPM": 1, "maxRPM": 2, "targetRPM": 1, "isManual": false]],
            [["index": 0, "actualRPM": 1, "minRPM": 0, "maxRPM": 2, "targetRPM": 1, "isManual": false]],
            [["index": 0, "actualRPM": 1, "minRPM": 2, "maxRPM": 1, "targetRPM": 1, "isManual": false]],
            [["index": 0, "actualRPM": 1, "minRPM": 1, "maxRPM": 2, "targetRPM": 100_001, "isManual": false]],
            [["index": 0, "actualRPM": 1, "minRPM": 1, "maxRPM": 2, "targetRPM": 1, "isManual": "no"]]
        ]
        XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: nil))
        XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: ["success": false]))
        for raw in invalidFans {
            XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: ["success": true, "fans": raw]))
        }

        let validSensors: [String: Any] = ["success": true, "sensors": [
            ["key": "Tp01", "value": NSNumber(value: 65.5)],
            ["key": "Tg01", "value": NSNumber(value: 55.0)],
            ["key": "Tm01", "value": NSNumber(value: 45.0)]
        ]]
        XCTAssertEqual(FanHelperProtocolParser.temperatureSamples(from: validSensors)?.count, 3)
        XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: nil))
        XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: ["success": true, "sensors": []]))
        for sensor in [
            ["key": "Bad", "value": NSNumber(value: 1)],
            ["key": "Tx01", "value": NSNumber(value: 1)],
            ["key": "Tp01", "value": true],
            ["key": "Tp01", "value": NSNumber(value: 0)],
            ["key": "Tp01", "value": NSNumber(value: 111)]
        ] as [[String: Any]] {
            XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: ["success": true, "sensors": [sensor]]))
        }

        var version = SMCVersion()
        version.major = 1
        var limits = SMCPLimitData()
        limits.cpuPLimit = 2
        var keyInfo = SMCKeyInfoData()
        keyInfo.dataSize = 32
        var keyData = SMCKeyData()
        keyData.key = 3
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(limits.cpuPLimit, 2)
        XCTAssertEqual(keyInfo.dataSize, 32)
        XCTAssertEqual(keyData.key, 3)
        XCTAssertTrue(FanCommandSafety.allows(index: 0, rpm: 2_000, fanCount: 1, minRPM: 1_000, maxRPM: 3_000))
    }
}
