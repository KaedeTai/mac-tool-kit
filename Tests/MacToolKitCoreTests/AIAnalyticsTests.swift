import XCTest
@testable import MacToolKitCore

final class AIAnalyticsTests: XCTestCase {
    func testPricingCalculator() throws {
        let pricing = AIPricingCalculator.shared

        // 1M input tokens on Sonnet = $3.00, 1M output tokens = $15.00
        let sonnetCost = pricing.calculateCostUSD(
            model: "claude-3-7-sonnet",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000,
            thinkingTokens: 0
        )
        // 3.0 + 15.0 + 0.30 = $18.30
        XCTAssertEqual(try XCTUnwrap(sonnetCost), 18.30, accuracy: 0.01)

        let sonnet35Cost = pricing.calculateCostUSD(
            model: "claude-3-5-sonnet-20241022",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        )
        XCTAssertEqual(try XCTUnwrap(sonnet35Cost), 18.00, accuracy: 0.01)

        // Local model = $0.00
        let localCost = pricing.calculateCostUSD(
            model: "deepseek-r1:14b",
            inputTokens: 500_000,
            outputTokens: 100_000
        )
        XCTAssertEqual(try XCTUnwrap(localCost), 0.0, accuracy: 0.001)

        XCTAssertNil(pricing.calculateCostUSD(
            model: "unknown-model",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000
        ))

        // Official Anthropic standard API rates captured 2026-08-28:
        // Haiku 4.5 input $1, 1h cache write $2, cache read $0.10, output $5 / MTok.
        let haiku45Cost = pricing.calculateCostUSD(
            model: "claude-haiku-4-5-20251001",
            inputTokens: 43,
            outputTokens: 5_809,
            cacheReadTokens: 23_792,
            cacheWrite1hTokens: 39_144
        )
        XCTAssertEqual(try XCTUnwrap(haiku45Cost), 0.1097552, accuracy: 0.0000001)

        let fable5Cost = pricing.calculateCostUSD(
            model: "claude-fable-5",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 1_000_000,
            cacheWrite1hTokens: 1_000_000
        )
        XCTAssertEqual(try XCTUnwrap(fable5Cost), 81.00, accuracy: 0.01)

        // Official OpenAI standard Work/Codex token rates captured 2026-08-28.
        // Cached input is a subset of input, so it must not also receive the full input rate.
        let codexCost = pricing.calculateCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            cacheReadTokens: 250_000
        )
        XCTAssertEqual(try XCTUnwrap(codexCost), 23.10, accuracy: 0.0001)

        let codexCacheWriteCost = pricing.calculateCostUSD(
            model: "gpt-5.6-sol",
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheWriteTokens: 1_000_000
        )
        XCTAssertEqual(try XCTUnwrap(codexCacheWriteCost), 5.00, accuracy: 0.0001)

        XCTAssertEqual(
            pricing.calculateCostUSD(model: "gpt-5.6-sol", inputTokens: 0, outputTokens: 0),
            0
        )
        XCTAssertNil(pricing.calculateCostUSD(
            model: "gpt-5.6-sol", inputTokens: -1, outputTokens: 0
        ))
        XCTAssertNil(pricing.calculateCostUSD(
            model: "gpt-5.6-sol", inputTokens: 100, outputTokens: 0, cacheReadTokens: 101
        ))
    }

    func testAISessionRecordDataIntegrity() {
        let tokenSummary = AITokenUsageSummary(
            inputTokens: 120_000,
            outputTokens: 30_000,
            cacheReadTokens: 80_000,
            cacheWriteTokens: 10_000,
            thinkingTokens: 5_000
        )

        // Thinking is a subset of output and must not be double-counted.
        XCTAssertEqual(tokenSummary.totalTokens, 240_000)

        let session = AISessionRecord(
            sessionId: "test-session-12345678",
            sessionShortId: "test-ses",
            toolType: .claudeCode,
            projectName: "🌿 Subagent (quizzical-kowalevski-b2c78d)",
            parentProjectName: "artogo-aeo-dashboard",
            projectPath: "/path/to/artogo-aeo-dashboard",
            gitBranch: "main",
            isSubagent: true,
            subagentSlug: "quizzical-kowalevski-b2c78d",
            startedAt: Date(),
            lastActiveAt: Date(),
            durationSeconds: 125.0,
            status: .active,
            livePID: 12345,
            liveCPU: 45.2,
            liveMemoryBytes: 250_000_000,
            totalTurns: 10,
            totalToolCalls: 8,
            modelsUsed: [
                AIModelUsage(
                    modelName: "claude-3-7-sonnet",
                    turnCount: 10,
                    inputTokens: 120_000,
                    outputTokens: 30_000,
                    cacheReadTokens: 80_000,
                    thinkingTokens: 5_000,
                    estimatedCostUSD: 0.85
                )
            ],
            taskBreakdown: [
                AITaskCategoryUsage(
                    category: .testing,
                    callCount: 4,
                    totalDurationMs: 12000,
                    tokenShare: 0.6,
                    estimatedCostUSD: 0.51
                )
            ],
            tokenUsage: tokenSummary,
            estimatedCostUSD: 0.85
        )

        XCTAssertEqual(session.parentProjectName, "artogo-aeo-dashboard")
        XCTAssertTrue(session.isSubagent)
        XCTAssertEqual(session.subagentSlug, "quizzical-kowalevski-b2c78d")
        XCTAssertEqual(session.status, .active)
        XCTAssertEqual(session.modelsUsed.first?.modelName, "claude-3-7-sonnet")
        XCTAssertEqual(session.taskBreakdown.first?.category, .testing)
        XCTAssertEqual(session.formattedDuration, "2 分 5 秒")
    }

    func testEngineSummaryGeneration() {
        let now = Date(timeIntervalSince1970: 100_000)
        let session = AISessionRecord(
            sessionId: "summary-fixture",
            toolType: .codex,
            title: "Summary fixture",
            projectName: "fixture-project",
            projectPath: "/tmp/fixture-project",
            startedAt: now.addingTimeInterval(-120),
            lastActiveAt: now.addingTimeInterval(-60),
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 10, outputTokens: 5, providerTotalTokens: 15),
            cost: .unavailable
        )
        let summary = AISessionAnalyticsEngine.buildSummary(sessions: [session], now: now)

        XCTAssertEqual(summary.activeSessions.count, 0)
        XCTAssertEqual(summary.recentSessions.count, 1)
        XCTAssertEqual(summary.historySessions.count, 0)
        XCTAssertEqual(summary.projectWorkspaces.first?.totalTokens, 15)
        XCTAssertNil(summary.projectWorkspaces.first?.actualCostUSD)
    }

    func testWorkspaceMarksEstimateIncompleteWhenAnyMeasuredUsageCannotBePriced() throws {
        let now = Date()
        let priced = AISessionRecord(
            sessionId: "priced",
            toolType: .claudeCode,
            projectName: "fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 1,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 100, outputTokens: 20),
            cost: .apiEquivalentEstimate(0.01, source: "official fixture")
        )
        let unpriced = AISessionRecord(
            sessionId: "unpriced",
            toolType: .codex,
            projectName: "fixture",
            projectPath: "/tmp/fixture",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 1,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: AITokenUsageSummary(inputTokens: 50, outputTokens: 10),
            cost: .unavailable(reason: "unknown model")
        )
        let workspace = try XCTUnwrap(
            AISessionAnalyticsEngine.buildSummary(sessions: [priced, unpriced], now: now)
                .projectWorkspaces.first
        )

        XCTAssertEqual(workspace.apiEquivalentEstimateUSD, 0.01)
        XCTAssertFalse(workspace.apiEquivalentEstimateIsComplete)
    }
}
