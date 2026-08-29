import XCTest
@testable import MacToolKitCore
import MacToolKitHardwareABI
import SQLite3

final class TrustworthyDashboardTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testTokenTotalUsesProviderTotalWithoutDoubleCountingCacheOrThinking() {
        let usage = AITokenUsageSummary(
            inputTokens: 100,
            outputTokens: 20,
            cacheReadTokens: 80,
            thinkingTokens: 5,
            providerTotalTokens: 120,
            source: .providerReported("rollout token_count")
        )

        XCTAssertEqual(usage.totalTokens, 120)
        XCTAssertEqual(usage.cacheReadTokens, 80)
        XCTAssertEqual(usage.thinkingTokens, 5)
    }

    func testAPIEstimateVisibilityRequiresBothUserOptInAndAProviderBasedEstimate() {
        let estimate = AICostValue.apiEquivalentEstimate(
            0.42,
            source: "Official API pricing snapshot 2026-08-28; API-equivalent estimate, not billing"
        )

        XCTAssertTrue(AISessionCostPresentation.shouldDisplay(estimate, estimatesEnabled: true))
        XCTAssertFalse(AISessionCostPresentation.shouldDisplay(estimate, estimatesEnabled: false))
        XCTAssertFalse(AISessionCostPresentation.shouldDisplay(.unavailable, estimatesEnabled: true))
    }

    func testThermalPresentationShowsOnlyMeasuredPhysicalSources() {
        let readings = [
            ComponentThermalReading(
                target: .socPackage,
                name: "SoC／PMU",
                locationDescription: "14 measured points",
                temperatureCelsius: 58.8,
                iconName: "cpu.fill"
            ),
            ComponentThermalReading(
                target: .gpuCore,
                name: "GPU",
                locationDescription: "No verified source",
                temperatureCelsius: nil,
                iconName: "gamecontroller.fill"
            ),
            ComponentThermalReading(
                target: .peakHotspot,
                name: "Derived maximum",
                locationDescription: "Maximum of available sources",
                temperatureCelsius: 58.8,
                iconName: "flame.fill",
                isHotspot: true
            ),
            ComponentThermalReading(
                target: .nvmeSSD,
                name: "NAND",
                locationDescription: "NAND CH0 temp",
                temperatureCelsius: 38.0,
                iconName: "internaldrive.fill"
            )
        ]

        let visible = ThermalSensorPresentation.measuredPhysicalReadings(from: readings)

        XCTAssertEqual(visible.map(\.target), [.socPackage, .nvmeSSD])
    }

    func testThermalPresentationCountsNamedPointsInsteadOfSummaryCards() {
        let readings = [
            ComponentThermalReading(
                target: .socPackage,
                name: "SoC／PMU",
                locationDescription: "2 measured points",
                temperatureCelsius: 58.8,
                iconName: "cpu.fill",
                measuredPoints: [
                    ComponentThermalPoint(name: "PMU tdie1", temperatureCelsius: 58.8, source: "Apple IOHID"),
                    ComponentThermalPoint(name: "PMU tdie2", temperatureCelsius: 55.0, source: "Apple IOHID")
                ]
            ),
            ComponentThermalReading(
                target: .palmRest,
                name: "Battery",
                locationDescription: "AppleSmartBattery",
                temperatureCelsius: 35.0,
                iconName: "hand.raised.fill",
                measuredPoints: [
                    ComponentThermalPoint(name: "AppleSmartBattery Temperature", temperatureCelsius: 35.0, source: "AppleSmartBattery")
                ]
            )
        ]

        XCTAssertEqual(ThermalSensorPresentation.measuredPointCount(from: readings), 3)
    }

    func testActivityOnlySessionsStayVisibleWhenActiveButAreOptionalInRecentAndHistory() {
        let activityOnly = AISessionRecord.fixture(
            sessionId: "activity-only",
            lastActiveAt: Date()
        )

        XCTAssertTrue(activityOnly.isActivityOnlyRecord)
        XCTAssertTrue(
            AISessionPresentation.shouldInclude(
                activityOnly,
                lifecycle: .active,
                showActivityOnlyRecords: false
            )
        )
        XCTAssertFalse(
            AISessionPresentation.shouldInclude(
                activityOnly,
                lifecycle: .recent,
                showActivityOnlyRecords: false
            )
        )
        XCTAssertFalse(
            AISessionPresentation.shouldInclude(
                activityOnly,
                lifecycle: .history,
                showActivityOnlyRecords: false
            )
        )
        XCTAssertTrue(
            AISessionPresentation.shouldInclude(
                activityOnly,
                lifecycle: .recent,
                showActivityOnlyRecords: true
            )
        )
    }

    func testLifecycleSeparatesUnknownRecentAndPermanentHistory() {
        let now = Date(timeIntervalSince1970: 1_000_000)

        XCTAssertEqual(
            AISessionLifecycle.classify(status: .unknown, lastActiveAt: now.addingTimeInterval(-60), now: now),
            .recent
        )
        XCTAssertEqual(
            AISessionLifecycle.classify(status: .completed, lastActiveAt: now.addingTimeInterval(-86_400), now: now),
            .history
        )
        XCTAssertEqual(
            AISessionLifecycle.classify(status: .thinking, lastActiveAt: now.addingTimeInterval(-200_000), now: now),
            .active
        )
        XCTAssertEqual(
            AISessionLifecycle.classify(status: .idle, lastActiveAt: now.addingTimeInterval(-60), now: now),
            .recent
        )
    }

    func testCodexParserReadsRolloutFactsAndLabelsStandardRateEstimate() throws {
        let root = try temporaryDirectory()
        let rollout = root.appendingPathComponent("rollout.jsonl")
        let lines = [
            #"{"timestamp":"2026-08-28T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-1","timestamp":"2026-08-28T01:00:00.000Z","cwd":"/tmp/factual-project","originator":"codex","model_provider":"openai"}}"#,
            #"{"timestamp":"2026-08-28T01:10:00.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-08-28T01:11:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":90,"reasoning_output_tokens":20,"total_tokens":1090}}}}"#
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(CodexTelemetryParser().parseSessionFile(url: rollout, title: "A"))
        XCTAssertEqual(record.sessionId, "thread-1")
        XCTAssertEqual(record.title, "A")
        XCTAssertEqual(record.projectPath, "/tmp/factual-project")
        XCTAssertEqual(record.parentProjectName, "factual-project")
        XCTAssertEqual(record.tokenUsage.totalTokens, 1090)
        XCTAssertEqual(record.tokenUsage.cacheReadTokens, 700)
        XCTAssertEqual(record.parentSessionId, nil)
        XCTAssertEqual(record.status, .unknown)
        XCTAssertEqual(record.cost.kind, .apiEquivalentEstimate)
        XCTAssertEqual(try XCTUnwrap(record.cost.amountUSD), 0.00328, accuracy: 0.000001)
        XCTAssertTrue(record.cost.source.detail.contains("2026-08-28"))
        XCTAssertTrue(record.cost.source.detail.contains("not billing"))
    }

    func testCodexMigratedRolloutUsesCanonicalThreadIDLatestCWDAndRootTitle() throws {
        let root = try temporaryDirectory()
        let sessions = root.appendingPathComponent("sessions/2026/08/28", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rootID = "01a023c2-6a39-7bb3-95a6-fa7a904e0041"
        let threadID = "01a03d16-b0ef-7183-8281-f9a589ecd567"
        let rollout = sessions.appendingPathComponent(
            "rollout-2026-08-28T01-00-00-\(rootID)_\(threadID).jsonl"
        )
        let lines = [
            #"{"timestamp":"2026-08-28T01:00:00.000Z","type":"session_meta","payload":{"id":"01a023c2-6a39-7bb3-95a6-fa7a904e0041","cwd":"/Users/example"}}"#,
            #"{"timestamp":"2026-08-28T01:01:00.000Z","type":"turn_context","payload":{"cwd":"/Users/example/Documents/program/hunterest","model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-08-28T01:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":20,"total_tokens":120}}}}"#
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)
        let index = root.appendingPathComponent("session_index.jsonl")
        try #"{"id":"01a023c2-6a39-7bb3-95a6-fa7a904e0041","thread_name":"Maker Studio billing"}"#
            .write(to: index, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(CodexTelemetryParser(codexDirectory: root).parseAllSessions().first)
        XCTAssertEqual(record.sessionId, threadID)
        XCTAssertEqual(record.title, "Maker Studio billing")
        XCTAssertEqual(record.projectPath, "/Users/example/Documents/program/hunterest")
    }

    func testCodexSubagentUsesExplicitParentThreadId() throws {
        let root = try temporaryDirectory()
        let rollout = root.appendingPathComponent("child.jsonl")
        let line = #"{"timestamp":"2026-08-28T01:00:00.000Z","type":"session_meta","payload":{"id":"child","parent_thread_id":"main","timestamp":"2026-08-28T01:00:00.000Z","cwd":"/tmp/project","source":{"subagent":"review"},"model_provider":"openai"}}"#
        try line.write(to: rollout, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(CodexTelemetryParser().parseSessionFile(url: rollout, title: nil))
        XCTAssertTrue(record.isSubagent)
        XCTAssertEqual(record.parentSessionId, "main")
        XCTAssertEqual(record.subagentSlug, "review")
    }

    func testCodexEstimateRequiresOneModelAcrossCompleteSessionScan() throws {
        let root = try temporaryDirectory()
        let rollout = root.appendingPathComponent("multi-model.jsonl")
        let lines = [
            #"{"timestamp":"2026-08-28T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-multi","cwd":"/tmp/project"}}"#,
            #"{"timestamp":"2026-08-28T01:00:01.000Z","type":"turn_context","payload":{"model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-08-28T01:00:02.000Z","type":"turn_context","payload":{"model":"gpt-5.6-terra"}}"#,
            #"{"timestamp":"2026-08-28T01:00:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":100,"total_tokens":1100}}}}"#
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(CodexTelemetryParser().parseSessionFile(url: rollout, title: nil))
        XCTAssertEqual(record.cost.kind, .unavailable)
        XCTAssertTrue(record.cost.source.detail.contains("multiple models"))
    }

    func testCodexModelScanFindsTurnContextOutsideBoundedMetadataWindow() throws {
        let root = try temporaryDirectory()
        let rollout = root.appendingPathComponent("large-rollout.jsonl")
        let padding = String(repeating: "x", count: 400_000)
        let lines = [
            #"{"timestamp":"2026-08-28T01:00:00.000Z","type":"session_meta","payload":{"id":"thread-large","cwd":"/tmp/project"}}"#,
            #"{"timestamp":"2026-08-28T01:00:01.000Z","type":"response_item","payload":{"type":"message","text":"\#(padding)"}}"#,
            #"{"timestamp":"2026-08-28T01:00:02.000Z","type":"turn_context","payload":{"cwd":"/tmp/latest-project","model":"gpt-5.6-sol"}}"#,
            #"{"timestamp":"2026-08-28T01:00:03.000Z","type":"response_item","payload":{"type":"message","text":"\#(padding)"}}"#,
            #"{"timestamp":"2026-08-28T01:00:04.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":500,"output_tokens":100,"total_tokens":1100}}}}"#
        ]
        try lines.joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(CodexTelemetryParser().parseSessionFile(url: rollout, title: nil))
        XCTAssertEqual(record.modelsUsed.map(\.modelName), ["gpt-5.6-sol"])
        XCTAssertEqual(record.projectPath, "/tmp/latest-project")
        XCTAssertEqual(record.cost.kind, .apiEquivalentEstimate)
    }

    func testAntigravityParserKeepsUnknownFieldsUnavailable() throws {
        let root = try temporaryDirectory()
        let transcript = root.appendingPathComponent("transcript.jsonl")
        let lines = [
            #"{"created_at":"2026-08-28T01:00:00.000Z","tool_calls":[{"name":"read"}]}"#,
            #"{"created_at":"2026-08-28T01:01:00.000Z"}"#
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(
            AntigravityTelemetryParser(brainDirectory: root)
                .parseTranscriptFile(url: transcript, conversationId: "ag-1")
        )
        XCTAssertEqual(record.projectName, "Unlinked Antigravity")
        XCTAssertTrue(record.projectPath.isEmpty)
        XCTAssertEqual(record.status, .unknown)
        XCTAssertEqual(record.tokenUsage.source.label, "不可取得")
        XCTAssertEqual(record.cost.kind, .unavailable)
        XCTAssertEqual(record.totalToolCalls, 1)
    }

    func testClaudeNestedSubagentUsesSessionIdAsParentAndNormalizesWorktree() throws {
        let root = try temporaryDirectory()
        let childFolder = root
            .appendingPathComponent("main-session", isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: childFolder, withIntermediateDirectories: true)
        let child = childFolder.appendingPathComponent("agent-child-7.jsonl")
        let lines = [
            #"{"sessionId":"main-session","agentId":"child-7","isSidechain":true,"cwd":"/tmp/my-project/.claude/worktrees/task-a","timestamp":"2026-08-28T01:00:00.000Z","type":"user"}"#,
            #"{"sessionId":"main-session","agentId":"child-7","isSidechain":true,"cwd":"/tmp/my-project/.claude/worktrees/task-a","timestamp":"2026-08-28T01:00:02.000Z","type":"assistant","message":{"model":"claude-test","usage":{"input_tokens":3,"cache_creation_input_tokens":5,"cache_read_input_tokens":7,"output_tokens":11}}}"#
        ]
        try lines.joined(separator: "\n").write(to: child, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(ClaudeCodeTelemetryParser().parseSessionFile(url: child))
        XCTAssertEqual(record.sessionId, "child-7")
        XCTAssertEqual(record.parentSessionId, "main-session")
        XCTAssertTrue(record.isSubagent)
        XCTAssertEqual(record.projectPath, "/tmp/my-project")
        XCTAssertEqual(record.parentProjectName, "my-project")
        XCTAssertEqual(record.tokenUsage.totalTokens, 26)
        XCTAssertEqual(record.cost.kind, .unavailable)
    }

    func testClaudeSessionWithoutUsageIsRetainedWithUnavailableTokens() throws {
        let root = try temporaryDirectory()
        let transcript = root.appendingPathComponent("main.jsonl")
        let line = #"{"sessionId":"main-no-usage","cwd":"/tmp/factual-project","timestamp":"2026-08-28T01:00:00.000Z","type":"user"}"#
        try line.write(to: transcript, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(ClaudeCodeTelemetryParser().parseSessionFile(url: transcript))
        XCTAssertEqual(record.sessionId, "main-no-usage")
        XCTAssertEqual(record.tokenUsage.source.label, "不可取得")
        XCTAssertEqual(record.cost.kind, .unavailable)
    }

    func testClaudeParserIgnoresUnpricedZeroUsageMessagesAndPricesKnownModel() throws {
        let root = try temporaryDirectory()
        let transcript = root.appendingPathComponent("haiku.jsonl")
        let lines = [
            #"{"sessionId":"haiku-session","cwd":"/tmp/factual-project","timestamp":"2026-08-28T01:00:00.000Z","type":"user","message":{"content":"fixture"}}"#,
            #"{"sessionId":"haiku-session","cwd":"/tmp/factual-project","timestamp":"2026-08-28T01:00:00.500Z","type":"assistant","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#,
            #"{"sessionId":"haiku-session","cwd":"/tmp/factual-project","timestamp":"2026-08-28T01:00:01.000Z","type":"assistant","message":{"model":"claude-haiku-4-5-20251001","usage":{"input_tokens":43,"output_tokens":5809,"cache_read_input_tokens":23792,"cache_creation_input_tokens":39144,"cache_creation":{"ephemeral_1h_input_tokens":39144,"ephemeral_5m_input_tokens":0},"service_tier":"standard","speed":"standard"}}}"#
        ]
        try lines.joined(separator: "\n").write(to: transcript, atomically: true, encoding: .utf8)

        let record = try XCTUnwrap(ClaudeCodeTelemetryParser().parseSessionFile(url: transcript))
        XCTAssertEqual(record.modelsUsed.map(\.modelName), ["claude-haiku-4-5-20251001"])
        XCTAssertEqual(record.cost.kind, .apiEquivalentEstimate)
        XCTAssertEqual(try XCTUnwrap(record.cost.amountUSD), 0.1097552, accuracy: 0.0000001)
        XCTAssertTrue(record.cost.source.detail.contains("2026-08-28"))
    }

    func testHistoryStoreRetainsSessionsMissingFromNextProviderScan() throws {
        let root = try temporaryDirectory()
        let store = AISessionHistoryStore(storeURL: root.appendingPathComponent("history.json"))
        let session = AISessionRecord.fixture(sessionId: "kept", lastActiveAt: Date(timeIntervalSince1970: 1))

        XCTAssertEqual(store.merge(current: [session]).count, 1)
        XCTAssertEqual(store.merge(current: []).map(\.sessionId), ["kept"])
        XCTAssertEqual(store.persistenceStatus().label, "實測")
    }

    func testPersistedSessionCannotRemainAuthoritativelyActive() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("history.json")
        let store = AISessionHistoryStore(storeURL: url)
        let now = Date()
        let active = AISessionRecord(
            sessionId: "active-before-restart",
            toolType: .codex,
            title: "Active fixture",
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .active,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        _ = store.merge(current: [active])

        let afterRestart = AISessionHistoryStore(storeURL: url).merge(current: [])
        XCTAssertEqual(afterRestart.first?.status, .completed)
    }

    func testHistoryRetainsOnlyProvenancedOfficialRateEstimate() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("history.json")
        let now = Date()
        let official = AISessionRecord(
            sessionId: "official-estimate",
            toolType: .codex,
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 1,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 10, outputTokens: 5),
            cost: .apiEquivalentEstimate(
                0.25,
                source: "Official OpenAI ChatGPT Work/Codex rate card standard token rates captured 2026-08-28; API-equivalent estimate, not billing"
            )
        )
        let unprovenanced = AISessionRecord(
            sessionId: "unprovenanced-estimate",
            toolType: .codex,
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 1,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 10, outputTokens: 5),
            cost: .apiEquivalentEstimate(999, source: "guessed fallback")
        )

        let store = AISessionHistoryStore(storeURL: url)
        _ = store.merge(current: [official, unprovenanced])
        let afterRestart = AISessionHistoryStore(storeURL: url).merge(current: [])

        XCTAssertEqual(afterRestart.first { $0.sessionId == "official-estimate" }?.cost.kind, .apiEquivalentEstimate)
        XCTAssertEqual(afterRestart.first { $0.sessionId == "unprovenanced-estimate" }?.cost.kind, .unavailable)
    }

    func testHistoryDoesNotErasePreviouslyCapturedTokenAndCostEvidence() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("history.json")
        let now = Date()
        let captured = AISessionRecord(
            sessionId: "evidence",
            toolType: .codex,
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 3,
            totalToolCalls: 2,
            modelsUsed: [AIModelUsage(
                modelName: "gpt-5.6-sol", turnCount: 3,
                inputTokens: 100, outputTokens: 20, cacheReadTokens: 50,
                thinkingTokens: 5, estimatedCostUSD: 0.001
            )],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 100, outputTokens: 20, providerTotalTokens: 120),
            cost: .apiEquivalentEstimate(
                0.001,
                source: "Official OpenAI ChatGPT Work/Codex rate card standard token rates captured 2026-08-28; API-equivalent estimate, not billing"
            )
        )
        let metadataOnly = AISessionRecord(
            sessionId: "evidence",
            toolType: .codex,
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now.addingTimeInterval(60),
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )

        let store = AISessionHistoryStore(storeURL: url)
        _ = store.merge(current: [captured])
        let merged = try XCTUnwrap(store.merge(current: [metadataOnly]).first)

        XCTAssertEqual(merged.tokenUsage.totalTokens, 120)
        XCTAssertEqual(merged.modelsUsed.map(\.modelName), ["gpt-5.6-sol"])
        XCTAssertEqual(merged.cost.kind, .apiEquivalentEstimate)
        XCTAssertEqual(merged.totalTurns, 3)
        XCTAssertEqual(merged.totalToolCalls, 2)
        XCTAssertEqual(merged.lastActiveAt, metadataOnly.lastActiveAt)
    }

    func testHistoryStoreNeverPersistsRawTurnDescriptionsFromCurrentScan() throws {
        let root = try temporaryDirectory()
        let url = root.appendingPathComponent("history.json")
        let now = Date()
        let record = AISessionRecord(
            sessionId: "private-turn",
            toolType: .codex,
            title: "Fixture",
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 1,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable,
            turns: [
                AITurnRecord(
                    turnIndex: 1,
                    timestamp: now,
                    durationMs: 0,
                    modelName: nil,
                    taskCategory: .other,
                    taskDescription: "must-not-be-persisted"
                )
            ]
        )

        _ = AISessionHistoryStore(storeURL: url).merge(current: [record])

        let persisted = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(persisted.contains("must-not-be-persisted"))
    }

    func testWorkspaceLinksChildrenOnlyByExplicitParentID() {
        let now = Date()
        let main = AISessionRecord.fixture(sessionId: "main", lastActiveAt: now)
        let child = AISessionRecord(
            sessionId: "child",
            toolType: .codex,
            title: "Child",
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            isSubagent: true,
            parentSessionId: "main",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        let summary = AISessionAnalyticsEngine.buildSummary(sessions: [main, child], now: now)
        XCTAssertEqual(summary.projectWorkspaces.first?.children(of: main).map(\.sessionId), ["child"])
        XCTAssertTrue(summary.projectWorkspaces.first?.unlinkedSubagentSessions.isEmpty == true)
    }

    func testWorkspaceDoesNotLinkSameSessionIDAcrossProvidersAndKeepsUnlinkedIDsUnique() throws {
        let now = Date()
        let codexMain = AISessionRecord.fixture(sessionId: "shared", lastActiveAt: now)
        let claudeChild = AISessionRecord(
            sessionId: "child",
            toolType: .claudeCode,
            title: "Child",
            projectName: "Fixture",
            projectPath: "/tmp/fixture",
            isSubagent: true,
            parentSessionId: "shared",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        let workspace = try XCTUnwrap(
            AISessionAnalyticsEngine.buildSummary(sessions: [codexMain, claudeChild], now: now)
                .projectWorkspaces.first
        )
        XCTAssertTrue(workspace.children(of: codexMain).isEmpty)
        XCTAssertEqual(workspace.unlinkedSubagentSessions.map(\.sessionId), ["child"])

        let first = AIProjectWorkspace(
            projectName: "Unlinked A", projectPath: "", totalTokens: 0,
            totalDurationSeconds: 0, sessionCount: 0, mainSessions: [], subagentSessions: []
        )
        let second = AIProjectWorkspace(
            projectName: "Unlinked B", projectPath: "", totalTokens: 0,
            totalDurationSeconds: 0, sessionCount: 0, mainSessions: [], subagentSessions: []
        )
        XCTAssertNotEqual(first.id, second.id)
    }

    func testHistoryTreeStartsCollapsedAndLoadsLargeProjectsInBoundedBatches() {
        let now = Date()
        let sessions = (0..<95).map {
            AISessionRecord.fixture(
                sessionId: "history-\($0)",
                projectPath: "/tmp/large-history",
                lastActiveAt: now.addingTimeInterval(-100_000 - Double($0))
            )
        }
        let workspace = AIProjectWorkspace(
            projectName: "large-history",
            projectPath: "/tmp/large-history",
            totalTokens: 0,
            totalDurationSeconds: 0,
            sessionCount: sessions.count,
            mainSessions: sessions,
            subagentSessions: []
        )

        var state = AISessionTreePresentationState(
            lifecycle: .history,
            workspaces: [workspace],
            batchSize: 40
        )

        XCTAssertFalse(state.isWorkspaceExpanded(workspace))
        XCTAssertTrue(state.visibleMainSessions(in: workspace).isEmpty)
        XCTAssertEqual(state.remainingMainSessionCount(in: workspace), 0)

        state.toggleWorkspace(workspace)
        XCTAssertEqual(state.visibleMainSessions(in: workspace).count, 40)
        XCTAssertEqual(state.remainingMainSessionCount(in: workspace), 55)

        state.loadMoreMainSessions(in: workspace)
        XCTAssertEqual(state.visibleMainSessions(in: workspace).count, 80)
        XCTAssertEqual(state.remainingMainSessionCount(in: workspace), 15)
    }

    func testActiveTreeStartsExpandedButMainSessionsRemainIndependentlyCollapsible() {
        let now = Date()
        let main = AISessionRecord.fixture(sessionId: "main", lastActiveAt: now)
        let child = AISessionRecord(
            sessionId: "child",
            toolType: .codex,
            title: "Child",
            projectName: "fixture",
            projectPath: "/tmp/fixture",
            isSubagent: true,
            parentSessionId: "main",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .active,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        let workspace = AIProjectWorkspace(
            projectName: "fixture",
            projectPath: "/tmp/fixture",
            totalTokens: 0,
            totalDurationSeconds: 0,
            sessionCount: 2,
            mainSessions: [main],
            subagentSessions: [child]
        )

        var state = AISessionTreePresentationState(
            lifecycle: .active,
            workspaces: [workspace]
        )

        XCTAssertTrue(state.isWorkspaceExpanded(workspace))
        XCTAssertTrue(state.isSessionExpanded(main))
        XCTAssertEqual(state.visibleChildren(of: main, in: workspace).map(\.sessionId), ["child"])

        state.toggleSession(main)
        XCTAssertFalse(state.isSessionExpanded(main))
        XCTAssertTrue(state.visibleChildren(of: main, in: workspace).isEmpty)
        XCTAssertEqual(state.remainingChildCount(of: main, in: workspace), 0)
    }

    func testRecentTreeRevealsTheSelectedChildWithoutExpandingOtherBranches() {
        let now = Date()
        let selectedMain = AISessionRecord.fixture(
            sessionId: "selected-main",
            projectPath: "/tmp/selected",
            lastActiveAt: now
        )
        let selectedChild = AISessionRecord(
            sessionId: "selected-child",
            toolType: .codex,
            title: "Selected child",
            projectName: "selected",
            projectPath: "/tmp/selected",
            isSubagent: true,
            parentSessionId: "selected-main",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .completed,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
        let selectedWorkspace = AIProjectWorkspace(
            projectName: "selected",
            projectPath: "/tmp/selected",
            totalTokens: 0,
            totalDurationSeconds: 0,
            sessionCount: 2,
            mainSessions: [selectedMain],
            subagentSessions: [selectedChild]
        )
        let otherMain = AISessionRecord.fixture(
            sessionId: "other-main",
            projectPath: "/tmp/other",
            lastActiveAt: now
        )
        let otherWorkspace = AIProjectWorkspace(
            projectName: "other",
            projectPath: "/tmp/other",
            totalTokens: 0,
            totalDurationSeconds: 0,
            sessionCount: 1,
            mainSessions: [otherMain],
            subagentSessions: []
        )

        var state = AISessionTreePresentationState(
            lifecycle: .recent,
            workspaces: [selectedWorkspace, otherWorkspace]
        )
        state.reveal(selectedChild, in: [selectedWorkspace, otherWorkspace])

        XCTAssertTrue(state.isWorkspaceExpanded(selectedWorkspace))
        XCTAssertTrue(state.isSessionExpanded(selectedMain))
        XCTAssertEqual(
            state.visibleChildren(of: selectedMain, in: selectedWorkspace).map(\.sessionId),
            ["selected-child"]
        )
        XCTAssertFalse(state.isWorkspaceExpanded(otherWorkspace))
    }

    func testHistoryDoesNotContinuouslyRescanThousandsOfPermanentRecords() {
        XCTAssertEqual(AISessionRefreshPolicy.interval(for: .active), 10)
        XCTAssertEqual(AISessionRefreshPolicy.interval(for: .recent), 30)
        XCTAssertNil(AISessionRefreshPolicy.interval(for: .history))
    }

    func testTelemetryFileCachePersistsOnlyMatchingFileVersion() throws {
        let root = try temporaryDirectory()
        let modified = Date(timeIntervalSince1970: 1_234.5)
        let record = AISessionRecord.fixture(sessionId: "cached", lastActiveAt: modified)

        let first = AITelemetryFileCache(name: "cache.json", directory: root)
        first.store(record: record, path: "/tmp/transcript.jsonl", modificationDate: modified, fileSize: 42)
        first.flush()

        let reloaded = AITelemetryFileCache(name: "cache.json", directory: root)
        XCTAssertEqual(
            reloaded.record(path: "/tmp/transcript.jsonl", modificationDate: modified, fileSize: 42)?.sessionId,
            "cached"
        )
        XCTAssertNil(reloaded.record(path: "/tmp/transcript.jsonl", modificationDate: modified, fileSize: 43))
    }

    func testNetworkCounterDeltaSupports64BitAndTreatsResetAsZero() {
        XCTAssertEqual(NetworkCounterDelta.bytes(current: 4_294_967_297, previous: 4_294_967_296), 1)
        XCTAssertEqual(NetworkCounterDelta.bytes(current: 4, previous: 100), 0)
    }

    func testCPUTopologyUsesReportedPerformanceLevelsWithoutGuessing() {
        let labels = CPUCoreTopology.labels(
            levels: [
                CPUPerformanceLevel(name: "Super", logicalCoreCount: 6),
                CPUPerformanceLevel(name: "Performance", logicalCoreCount: 12)
            ],
            totalCoreCount: 18
        )

        XCTAssertEqual(Array(labels.prefix(6)), Array(repeating: "Super*", count: 6))
        XCTAssertEqual(Array(labels.suffix(12)), Array(repeating: "Performance*", count: 12))
    }

    func testCommandLineRedactorRemovesCommonSecretForms() {
        let input = "tool --api-key sk-live-secret --token=abc123 PASSWORD=hunter2 https://user:pass@example.com/path"
        let redacted = CommandLineRedactor.redact(input)

        XCTAssertFalse(redacted.contains("sk-live-secret"))
        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("hunter2"))
        XCTAssertFalse(redacted.contains("user:pass"))
        XCTAssertTrue(redacted.contains("[REDACTED]"))
    }

    func testFanWriteRequiresEveryRequestedFanToSucceed() {
        XCTAssertTrue(FanWriteOutcome.allSucceeded([true, true]))
        XCTAssertFalse(FanWriteOutcome.allSucceeded([true, false]))
        XCTAssertFalse(FanWriteOutcome.allSucceeded([]))
    }

    func testAppleSMCParameterPayloadIsExactly80Bytes() {
        XCTAssertEqual(MemoryLayout<SMCKeyData>.size, 80)
        XCTAssertEqual(MemoryLayout<SMCKeyData>.stride, 80)
    }

    func testFanHelperCapabilityRequiresMeasuredFanReadbackNotOnlyPing() {
        XCTAssertEqual(
            FanHelperProtocolParser.capability(
                pingSucceeded: true,
                fanResponse: ["success": false, "error": "FNum unavailable or no fans reported"]
            ),
            .reachableWithoutReadback
        )
        XCTAssertEqual(
            FanHelperProtocolParser.capability(
                pingSucceeded: true,
                fanResponse: ["success": true, "fans": [validFanPayload(index: 0)]]
            ),
            .ready(fanCount: 1)
        )
        XCTAssertEqual(
            FanHelperProtocolParser.capability(pingSucceeded: false, fanResponse: nil),
            .unreachable
        )
    }

    func testFanHelperProtocolRejectsMalformedOrUnsafeFanPayloads() {
        XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: ["success": true, "fans": []]))
        XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: [
            "success": true,
            "fans": [validFanPayload(index: 0), validFanPayload(index: 0)]
        ]))
        XCTAssertNil(FanHelperProtocolParser.fanStatuses(from: [
            "success": true,
            "fans": [[
                "index": 0, "name": "Injected", "actualRPM": 999_999,
                "minRPM": 1_350, "maxRPM": 5_349, "targetRPM": 2_000, "isManual": false
            ]]
        ]))
        XCTAssertEqual(
            FanHelperProtocolParser.fanStatuses(from: [
                "success": true,
                "fans": [validFanPayload(index: 0), validFanPayload(index: 1)]
            ])?.count,
            2
        )
    }

    func testFanCommandSafetyRejectsInvalidIndexAndOutOfRangeRPM() {
        XCTAssertTrue(FanCommandSafety.allows(index: 0, rpm: 3_000, fanCount: 2, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: -1, rpm: 3_000, fanCount: 2, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: 2, rpm: 3_000, fanCount: 2, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: 0, rpm: 0, fanCount: 2, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: 0, rpm: 99_999, fanCount: 2, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: 0, rpm: 3_000, fanCount: 0, minRPM: 1_350, maxRPM: 5_349))
        XCTAssertFalse(FanCommandSafety.allows(index: 0, rpm: 3_000, fanCount: 2, minRPM: 6_000, maxRPM: 5_000))
    }

    func testTemperatureProtocolRejectsDuplicateMalformedAndImpossibleSamples() {
        XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: [
            "success": true,
            "sensors": [["key": "Tp00", "value": 60.0], ["key": "Tp00", "value": 61.0]]
        ]))
        XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: [
            "success": true,
            "sensors": [["key": "Tp00\nINJECT", "value": 60.0]]
        ]))
        XCTAssertNil(FanHelperProtocolParser.temperatureSamples(from: [
            "success": true,
            "sensors": [["key": "Tp00", "value": 500.0]]
        ]))
        XCTAssertEqual(FanHelperProtocolParser.temperatureSamples(from: [
            "success": true,
            "sensors": [["key": "Tp00", "value": 60.0], ["key": "Tg00", "value": 61.0]]
        ])?.count, 2)
    }

    func testSMCTemperatureKeysAreNotPromotedToNamedComponentsWithoutAProvenMapping() {
        let base = HardwareSensorMonitor().sampleAllComponents()
        let readings = SMCTemperatureReducer.merge(
            samples: [
                SMCTemperatureSample(key: "Tp00", valueCelsius: 61.5),
                SMCTemperatureSample(key: "Tp01", valueCelsius: 72.25),
                SMCTemperatureSample(key: "Tg00", valueCelsius: 64.5),
                SMCTemperatureSample(key: "Tm00", valueCelsius: 58.0),
                SMCTemperatureSample(key: "TG0B", valueCelsius: 99.0),
                SMCTemperatureSample(key: "TpXX", valueCelsius: 500.0),
                SMCTemperatureSample(key: "evil", valueCelsius: 80.0)
            ],
            into: base
        )

        XCTAssertNil(readings.first(where: { $0.target == .cpuPackage })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .gpuCore })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .memoryRAM })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .aneEngine })?.temperatureCelsius)
        XCTAssertFalse(readings.contains { $0.locationDescription.contains("Tp*") })
    }

    func testHIDTemperatureReducerUsesOnlyNamedMeasuredFamiliesAndDeduplicatesProducts() {
        let base = ThermalSensorTarget.allCases
            .filter { $0 != .peakHotspot }
            .map {
                ComponentThermalReading(
                    target: $0,
                    name: $0.shortName,
                    locationDescription: "目前沒有可驗證的硬體感測來源",
                    temperatureCelsius: nil,
                    iconName: $0.iconName
                )
            }
        let readings = HIDTemperatureReducer.merge(
            samples: [
                HIDTemperatureSample(productName: "PMU tdie1", valueCelsius: 71.5),
                HIDTemperatureSample(productName: "PMU tdie1", valueCelsius: 72.25),
                HIDTemperatureSample(productName: "PMU tdie2", valueCelsius: 66.0),
                HIDTemperatureSample(productName: "PMU tcal", valueCelsius: 99.0),
                HIDTemperatureSample(productName: "NAND CH0 temp", valueCelsius: 43.0),
                HIDTemperatureSample(productName: "gas gauge battery", valueCelsius: 35.5),
                HIDTemperatureSample(productName: "PMU tdie3", valueCelsius: 500.0)
            ],
            into: base
        )

        XCTAssertEqual(readings.first(where: { $0.target == .socPackage })?.temperatureCelsius, 72.25)
        XCTAssertEqual(readings.first(where: { $0.target == .nvmeSSD })?.temperatureCelsius, 43.0)
        XCTAssertEqual(readings.first(where: { $0.target == .palmRest })?.temperatureCelsius, 35.5)
        XCTAssertEqual(readings.first(where: { $0.target == .peakHotspot })?.temperatureCelsius, 72.25)
        XCTAssertNil(readings.first(where: { $0.target == .cpuPackage })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .gpuCore })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .aneEngine })?.temperatureCelsius)
        XCTAssertNil(readings.first(where: { $0.target == .memoryRAM })?.temperatureCelsius)
        XCTAssertTrue(readings.first(where: { $0.target == .socPackage })?.locationDescription.contains("2 個具名實測點") == true)
        XCTAssertEqual(
            readings.first(where: { $0.target == .socPackage })?.measuredPoints.map(\.name),
            ["PMU tdie1", "PMU tdie2"]
        )
        XCTAssertEqual(
            readings.first(where: { $0.target == .socPackage })?.measuredPoints.map(\.temperatureCelsius),
            [72.25, 66.0]
        )
        XCTAssertEqual(
            readings.first(where: { $0.target == .nvmeSSD })?.measuredPoints.map(\.name),
            ["NAND CH0 temp"]
        )
        XCTAssertEqual(
            readings.first(where: { $0.target == .palmRest })?.measuredPoints.map(\.name),
            ["gas gauge battery"]
        )
    }

    func testCodexRuntimeStatusProbeReadsLatestTurnPerThread() throws {
        let root = try temporaryDirectory()
        let database = root.appendingPathComponent("thread_history.sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &handle), SQLITE_OK)
        defer { sqlite3_close(handle) }
        XCTAssertEqual(sqlite3_exec(handle, """
            CREATE TABLE thread_turns (
                thread_id TEXT NOT NULL,
                turn_id TEXT NOT NULL,
                rollout_ordinal INTEGER NOT NULL,
                status TEXT NOT NULL,
                PRIMARY KEY (thread_id, turn_id)
            );
            INSERT INTO thread_turns VALUES ('active-thread', 'turn-1', 1, 'completed');
            INSERT INTO thread_turns VALUES ('active-thread', 'turn-2', 2, 'inProgress');
            INSERT INTO thread_turns VALUES ('done-thread', 'turn-1', 1, 'inProgress');
            INSERT INTO thread_turns VALUES ('done-thread', 'turn-2', 2, 'completed');
            CREATE TABLE thread_items (
                thread_id TEXT NOT NULL,
                rollout_ordinal INTEGER NOT NULL,
                item_type TEXT NOT NULL,
                item_json TEXT NOT NULL
            );
            INSERT INTO thread_items VALUES ('active-thread', 3, 'commandExecution', '{"cwd":"/tmp/old"}');
            INSERT INTO thread_items VALUES ('active-thread', 4, 'commandExecution', '{"cwd":"/tmp/current-project"}');
            """, nil, nil, nil), SQLITE_OK)

        let probe = CodexRuntimeStatusProbe(databaseURL: database)
        let states = probe.latestThreadStates()
        XCTAssertEqual(states["active-thread"], .inProgress)
        XCTAssertEqual(states["done-thread"], .completed)
        XCTAssertEqual(probe.latestExecutionWorkingDirectories()["active-thread"], "/tmp/current-project")
    }

    func testRuntimeReconcilerProducesActiveIdleOrInactiveWithoutUnknown() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let codex = AISessionRecord.fixture(sessionId: "codex-active", lastActiveAt: now.addingTimeInterval(-600))
        let claudeFresh = AISessionRecord.fixture(
            sessionId: "claude-fresh",
            toolType: .claudeCode,
            projectPath: "/tmp/claude-project",
            lastActiveAt: now.addingTimeInterval(-5)
        )
        let claudeIdle = AISessionRecord.fixture(
            sessionId: "claude-idle",
            toolType: .claudeCode,
            projectPath: "/tmp/claude-project",
            lastActiveAt: now.addingTimeInterval(-600)
        )
        let claudeHistory = AISessionRecord.fixture(
            sessionId: "claude-history",
            toolType: .claudeCode,
            projectPath: "/tmp/claude-project",
            lastActiveAt: now.addingTimeInterval(-172_800)
        )
        let antigravityInactive = AISessionRecord.fixture(
            sessionId: "antigravity-old",
            toolType: .antigravity,
            projectPath: "/tmp/no-process",
            lastActiveAt: now.addingTimeInterval(-600)
        )
        let reconciled = AISessionRuntimeReconciler.reconcile(
            records: [codex, claudeFresh, claudeIdle, claudeHistory, antigravityInactive],
            codexStates: ["codex-active": .inProgress],
            codexExecutionCWDs: ["codex-active": "/tmp/codex-project"],
            processes: [
                AIProviderProcessEvidence(
                    toolType: .claudeCode,
                    pid: 42,
                    workingDirectory: "/tmp/claude-project"
                )
            ],
            now: now,
            activityWindow: 30
        )

        XCTAssertEqual(reconciled.first { $0.sessionId == "codex-active" }?.status, .active)
        XCTAssertEqual(reconciled.first { $0.sessionId == "codex-active" }?.projectPath, "/tmp/codex-project")
        XCTAssertEqual(reconciled.first { $0.sessionId == "claude-fresh" }?.status, .active)
        XCTAssertEqual(reconciled.first { $0.sessionId == "claude-idle" }?.status, .idle)
        XCTAssertEqual(reconciled.first { $0.sessionId == "claude-history" }?.status, .completed)
        XCTAssertEqual(reconciled.first { $0.sessionId == "antigravity-old" }?.status, .completed)
        XCTAssertFalse(reconciled.contains { $0.status == .unknown })
    }

    func testSessionSelectionMovesIntoNewVisibleScope() {
        let now = Date()
        let recent = AISessionRecord.fixture(sessionId: "recent", lastActiveAt: now)
        let active = AISessionRecord.fixture(sessionId: "active", lastActiveAt: now)

        XCTAssertEqual(
            AISessionScopeSelection.reconcile(current: recent, visibleSessions: [active])?.sessionId,
            "active"
        )
        XCTAssertNil(AISessionScopeSelection.reconcile(current: recent, visibleSessions: []))
        XCTAssertEqual(
            AISessionScopeSelection.reconcile(current: active, visibleSessions: [active])?.sessionId,
            "active"
        )
    }

    func testFanHelperSocketTrustFailsClosedForWorldWritableOrWrongOwner() {
        XCTAssertEqual(
            FanHelperSocketTrust.evaluate(mode: 0o140660, ownerUID: 0, groupGID: 80),
            .trusted
        )
        XCTAssertEqual(
            FanHelperSocketTrust.evaluate(mode: 0o140666, ownerUID: 0, groupGID: 80),
            .unsafe("Socket permissions must be exactly 0660")
        )
        XCTAssertEqual(
            FanHelperSocketTrust.evaluate(mode: 0o140660, ownerUID: 501, groupGID: 80),
            .unsafe("Socket owner must be root")
        )
        XCTAssertEqual(
            FanHelperSocketTrust.evaluate(mode: 0o100660, ownerUID: 0, groupGID: 80),
            .unsafe("Helper endpoint is not a UNIX socket")
        )
    }

    func testDockerStatsJoinUsesDockerPSAsStatusAndMetadataSource() {
        let stats = #"{"Container":"abc123full","ID":"abc123","Name":"db","CPUPerc":"1.25%","MemUsage":"100MiB / 1GiB","MemPerc":"9.77%"}"#
        let ps = #"{"ID":"abc123full","Names":"db","Image":"postgres:17","State":"running","Status":"Up 2 hours (healthy)","RunningFor":"2 hours ago","Command":"postgres"}"#

        let result = ProcessMonitor.parseDockerContainers(statsOutput: stats, psOutput: ps)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].containerId, "abc123")
        XCTAssertEqual(result[0].image, "postgres:17")
        XCTAssertEqual(result[0].status, "Up 2 hours (healthy)")
        XCTAssertEqual(result[0].runningFor, "2 hours ago")
        XCTAssertEqual(result[0].command, "postgres")
        XCTAssertEqual(result[0].cpuPercentage, 1.25)
        XCTAssertEqual(result[0].memoryPercentage, 9.77)
    }

    func testDockerStatsJoinFailsClosedWhenPSMetadataIsMissing() {
        let stats = #"{"Container":"abc123full","ID":"abc123","Name":"db","CPUPerc":"0.00%","MemUsage":"0B / 1GiB","MemPerc":"0.00%"}"#

        let result = ProcessMonitor.parseDockerContainers(statsOutput: stats, psOutput: "")

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].status, "不可取得")
        XCTAssertEqual(result[0].image, "")
    }

    func testBatterySnapshotDefaultsDoNotInventMeasurements() {
        let snapshot = BatteryThermalSnapshot()
        XCTAssertNil(snapshot.batteryPercentage)
        XCTAssertNil(snapshot.healthPercentage)
        XCTAssertNil(snapshot.cycleCount)
        XCTAssertNil(snapshot.batteryTemperatureCelsius)
        XCTAssertNil(snapshot.powerWattage)
    }

    func testHardwareSensorMonitorOnlyPopulatesProvenNamedTemperatureFamilies() {
        let readings = HardwareSensorMonitor().sampleAllComponents()
        XCTAssertEqual(readings.count, ThermalSensorTarget.allCases.count)
        let neverAttributed: Set<ThermalSensorTarget> = [
            .cpuPackage, .gpuCore, .aneEngine, .memoryRAM, .heatsink
        ]
        for reading in readings where neverAttributed.contains(reading.target) {
            XCTAssertNil(reading.temperatureCelsius, "\(reading.target) must not be inferred")
            XCTAssertTrue(reading.locationDescription.contains("沒有可驗證"))
        }
        for reading in readings where reading.temperatureCelsius != nil {
            XCTAssertTrue(
                [.socPackage, .palmRest, .nvmeSSD, .peakHotspot].contains(reading.target),
                "Only named IOHID/AppleSmartBattery families may be populated"
            )
        }
    }

    func testFanProfileDescriptionsCoverEveryModeWithoutClaimingReadback() {
        let modes: [FanMode] = [
            .automatic,
            .quiet(targetTemp: 75),
            .balanced(targetTemp: 65),
            .maxCooling,
            .custom(rpm: 3_000)
        ]
        XCTAssertEqual(Set(modes.map(\.title)).count, modes.count)
        XCTAssertNil(FanMode.automatic.targetTemperatureCelsius)
        XCTAssertEqual(FanMode.custom(rpm: 3_000).targetTemperatureCelsius, nil)
    }
}

private extension TrustworthyDashboardTests {
    func validFanPayload(index: Int) -> [String: Any] {
        [
            "index": index,
            "name": "Fan \(index + 1)",
            "actualRPM": 1_500,
            "minRPM": 1_350,
            "maxRPM": 5_500,
            "targetRPM": 1_600,
            "isManual": false
        ]
    }
}

private extension AISessionRecord {
    static func fixture(
        sessionId: String,
        toolType: AIToolType = .codex,
        projectPath: String = "/tmp/fixture",
        lastActiveAt: Date
    ) -> AISessionRecord {
        AISessionRecord(
            sessionId: sessionId,
            toolType: toolType,
            title: "Fixture",
            projectName: URL(fileURLWithPath: projectPath).lastPathComponent,
            projectPath: projectPath,
            startedAt: lastActiveAt,
            lastActiveAt: lastActiveAt,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: .unavailable
        )
    }
}
