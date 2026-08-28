import XCTest
@testable import MacToolKitCore

final class AIAnalyticsTests: XCTestCase {
    func testPricingCalculator() {
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
        XCTAssertEqual(sonnetCost, 18.30, accuracy: 0.01)

        // Local model = $0.00
        let localCost = pricing.calculateCostUSD(
            model: "deepseek-r1:14b",
            inputTokens: 500_000,
            outputTokens: 100_000
        )
        XCTAssertEqual(localCost, 0.0, accuracy: 0.001)
    }

    func testAISessionRecordDataIntegrity() {
        let tokenSummary = AITokenUsageSummary(
            inputTokens: 120_000,
            outputTokens: 30_000,
            cacheReadTokens: 80_000,
            cacheWriteTokens: 10_000,
            thinkingTokens: 5_000
        )

        XCTAssertEqual(tokenSummary.totalTokens, 245_000)

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
        let engine = AISessionAnalyticsEngine.shared
        let summary = engine.fetchSummary(forceRefresh: true)

        // Engine should safely return summary with hierarchical workspaces
        XCTAssertNotNil(summary)
        XCTAssertGreaterThanOrEqual(summary.totalSessionsCount, 0)
        XCTAssertGreaterThanOrEqual(summary.projectWorkspaces.count, 0)

        print("\n================== REAL WORLD SUMMARY ==================")
        print("Active Sessions Count: \(summary.activeSessions.count)")
        for a in summary.activeSessions {
            print("  🟢 ACTIVE: [\(a.parentProjectName)] \(a.projectName) | PID: \(a.livePID ?? 0) | CPU: \(a.liveCPU ?? 0)% | Path: \(a.projectPath)")
        }

        print("\nProject Workspaces Count: \(summary.projectWorkspaces.count)")
        for ws in summary.projectWorkspaces {
            print("📁 WORKSPACE: [\(ws.projectName)] (Mains: \(ws.mainSessions.count), Subs: \(ws.subagentSessions.count), Tokens: \(ws.totalTokens), Cost: $\(String(format: "%.2f", ws.totalCostUSD)))")
            for m in ws.mainSessions {
                print("   👑 Main: #\(m.sessionShortId) | Cost: $\(String(format: "%.2f", m.estimatedCostUSD)) | Range: \(m.formattedTimeRange)")
            }
            for s in ws.subagentSessions {
                print("   🌿 Sub: (\(s.subagentSlug ?? "sub")) | Cost: $\(String(format: "%.2f", s.estimatedCostUSD)) | Range: \(s.formattedTimeRange)")
            }
        }
        print("========================================================\n")
    }
}
