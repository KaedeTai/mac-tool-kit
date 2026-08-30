import XCTest
@testable import MacToolKitCore

final class CoverageExpansionTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDashboardEngineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func session(
        id: String,
        tool: AIToolType = .codex,
        status: AISessionStatus = .completed,
        age: TimeInterval = 60,
        project: String = "project",
        path: String = "/tmp/project",
        isSubagent: Bool = false,
        parent: String? = nil,
        tokens: Int64 = 10,
        cost: AICostValue = .apiEquivalentEstimate(
            0.25,
            source: "Official OpenAI rate captured 2026-08-28; not billing"
        ),
        models: [AIModelUsage] = [],
        tasks: [AITaskCategoryUsage] = []
    ) -> AISessionRecord {
        AISessionRecord(
            sessionId: id,
            toolType: tool,
            title: "Title \(id)",
            projectName: project,
            parentProjectName: project,
            projectPath: path,
            gitBranch: "main",
            isSubagent: isSubagent,
            parentSessionId: parent,
            subagentSlug: isSubagent ? id : nil,
            startedAt: now.addingTimeInterval(-age - 120),
            lastActiveAt: now.addingTimeInterval(-age),
            durationSeconds: 125,
            status: status,
            totalTurns: 2,
            totalToolCalls: 1,
            modelsUsed: models,
            taskBreakdown: tasks,
            tokenUsage: tokens > 0
                ? AITokenUsageSummary(inputTokens: tokens - 1, outputTokens: 1, providerTotalTokens: tokens)
                : .unavailable,
            cost: cost
        )
    }

    func testAIEnumPresentationAndProvenanceCoverEveryCase() {
        XCTAssertEqual(AIToolType.allCases.map(\.id), AIToolType.allCases.map(\.rawValue))
        XCTAssertEqual(
            AIToolType.allCases.map(\.iconName),
            [
                "terminal.fill", "brain.head.profile", "cube.transparent.fill",
                "chevron.left.forwardslash.chevron.right", "cpu", "sparkles"
            ]
        )

        XCTAssertEqual(AISessionStatus.allCases.map(\.id), AISessionStatus.allCases.map(\.rawValue))
        XCTAssertEqual(
            AISessionStatus.allCases.map(\.statusColorName),
            ["orange", "blue", "purple", "blue", "green", "secondary", "red"]
        )

        let provenances: [AIDataProvenance] = [
            .measured("m"), .providerReported("p"), .derived("d"),
            .estimated("e"), .unavailable("u")
        ]
        XCTAssertEqual(provenances.map(\.label), ["實測", "供應商回報", "衍生", "估算", "不可取得"])
        XCTAssertEqual(provenances.map(\.detail), ["m", "p", "d", "e", "u"])

        XCTAssertEqual(AITaskCategory.allCases.map(\.id), AITaskCategory.allCases.map(\.rawValue))
        XCTAssertEqual(
            AITaskCategory.allCases.map(\.iconName),
            [
                "checkmark.diamond.fill", "pencil.and.ruler.fill", "text.magnifyingglass",
                "lightbulb.fill", "terminal", "globe", "ellipsis.bubble.fill"
            ]
        )
    }

    func testAISessionLifecycleSelectionAndPresentationBoundaries() throws {
        XCTAssertEqual(AISessionLifecycle.allCases.map(\.id), ["active", "recent", "history"])
        for status in [AISessionStatus.active, .thinking, .executingTool] {
            XCTAssertEqual(
                AISessionLifecycle.classify(status: status, lastActiveAt: now.addingTimeInterval(-100_000), now: now),
                .active
            )
        }
        for status in [AISessionStatus.idle, .unknown, .completed, .aborted] {
            XCTAssertEqual(
                AISessionLifecycle.classify(status: status, lastActiveAt: now.addingTimeInterval(-86_399), now: now),
                .recent
            )
            XCTAssertEqual(
                AISessionLifecycle.classify(status: status, lastActiveAt: now.addingTimeInterval(-86_400), now: now),
                .history
            )
        }

        let first = session(id: "first")
        let second = session(id: "second")
        XCTAssertEqual(AISessionScopeSelection.reconcile(current: nil, visibleSessions: [first, second])?.id, first.id)
        XCTAssertEqual(AISessionScopeSelection.reconcile(current: second, visibleSessions: [first, second])?.id, second.id)
        XCTAssertEqual(AISessionScopeSelection.reconcile(current: session(id: "missing"), visibleSessions: [first])?.id, first.id)
        XCTAssertNil(AISessionScopeSelection.reconcile(current: nil, visibleSessions: []))

        let activityOnly = session(id: "activity", tokens: 0, cost: .unavailable)
        XCTAssertTrue(activityOnly.isActivityOnlyRecord)
        XCTAssertTrue(AISessionPresentation.shouldInclude(activityOnly, lifecycle: .active, showActivityOnlyRecords: false))
        XCTAssertFalse(AISessionPresentation.shouldInclude(activityOnly, lifecycle: .recent, showActivityOnlyRecords: false))
        XCTAssertTrue(AISessionPresentation.shouldInclude(activityOnly, lifecycle: .history, showActivityOnlyRecords: true))
        XCTAssertFalse(session(id: "usage").isActivityOnlyRecord)

        let noCostProvided = AISessionRecord(
            sessionId: "no-cost",
            toolType: .other,
            projectName: "project",
            projectPath: "/tmp/project",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 0,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable
        )
        XCTAssertEqual(noCostProvided.cost.kind, .unavailable)
    }

    func testAIValueModelsDerivedFieldsAndRoundTrip() throws {
        XCTAssertEqual(AICostValue.unavailable.kind, .unavailable)
        XCTAssertEqual(AICostValue.unavailable(reason: "why").source.detail, "why")
        XCTAssertEqual(AICostValue.apiEquivalentEstimate(1.5, source: "rate").amountUSD, 1.5)

        let tokens = AITokenUsageSummary(
            inputTokens: 10,
            outputTokens: 5,
            cacheReadTokens: 3,
            cacheWriteTokens: 2,
            thinkingTokens: 4
        )
        XCTAssertEqual(tokens.totalTokens, 20)
        XCTAssertEqual(AITokenUsageSummary(inputTokens: 10, outputTokens: 5, providerTotalTokens: 99).totalTokens, 99)
        XCTAssertEqual(AITokenUsageSummary.unavailable.totalTokens, 0)

        let model = AIModelUsage(
            modelName: "model",
            turnCount: 2,
            inputTokens: 10,
            outputTokens: 5,
            cacheReadTokens: 3,
            thinkingTokens: 1,
            estimatedCostUSD: 0.2
        )
        XCTAssertEqual(model.id, "model")
        let task = AITaskCategoryUsage(
            category: .testing,
            callCount: 2,
            totalDurationMs: 500,
            tokenShare: 0.5,
            estimatedCostUSD: 0.1
        )
        XCTAssertEqual(task.id, AITaskCategory.testing.rawValue)
        let turn = AITurnRecord(
            turnIndex: 3,
            timestamp: now,
            durationMs: 20,
            modelName: "model",
            taskCategory: .testing,
            taskDescription: "test",
            inputTokens: 1,
            outputTokens: 2,
            cacheReadTokens: 3,
            thinkingTokens: 4
        )
        XCTAssertTrue(turn.id.hasPrefix("3_"))

        let actual = AISessionRecord(
            sessionId: "actual-session",
            toolType: .other,
            projectName: "fallback-title",
            projectPath: "",
            startedAt: now,
            lastActiveAt: now.addingTimeInterval(-5),
            durationSeconds: -1,
            status: .unknown,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [],
            taskBreakdown: [],
            tokenUsage: .unavailable,
            cost: AICostValue(amountUSD: 2, kind: .actualBilling, source: .providerReported("bill")),
            turns: [turn]
        )
        XCTAssertEqual(actual.sessionShortId, "actual-s")
        XCTAssertEqual(actual.title, "fallback-title")
        XCTAssertEqual(actual.parentProjectName, "fallback-title")
        XCTAssertEqual(actual.actualCostUSD, 2)
        XCTAssertEqual(actual.estimatedCostUSD, 0)
        XCTAssertEqual(actual.transcriptSpanSeconds, 0)
        XCTAssertEqual(actual.formattedDuration, "0 秒")
        XCTAssertTrue(actual.formattedTimeRange.contains("歷時 0 秒"))
        XCTAssertEqual(actual.turns, [turn])

        XCTAssertEqual(session(id: "seconds").formattedDuration, "2 分 5 秒")
        let hour = AISessionRecord(
            sessionId: "hour",
            toolType: .codex,
            projectName: "p",
            projectPath: "/p",
            startedAt: now,
            lastActiveAt: now,
            durationSeconds: 3_665,
            status: .completed,
            totalTurns: 0,
            totalToolCalls: 0,
            modelsUsed: [model],
            taskBreakdown: [task],
            tokenUsage: tokens,
            estimatedCostUSD: 1.2
        )
        XCTAssertEqual(hour.formattedDuration, "1 小時 1 分")
        XCTAssertEqual(hour.estimatedCostUSD, 1.2)
        XCTAssertFalse(hour.isActivityOnlyRecord)

        let data = try JSONEncoder().encode(hour)
        let decoded = try JSONDecoder().decode(AISessionRecord.self, from: data)
        XCTAssertEqual(decoded.sessionId, "hour")
    }

    func testWorkspaceSummaryAndAnalyticsInitializers() {
        let active = session(id: "main", status: .active, models: [
            AIModelUsage(modelName: "m", turnCount: 1, inputTokens: 8, outputTokens: 2, cacheReadTokens: 0, thinkingTokens: 0, estimatedCostUSD: 0.2)
        ])
        let linked = session(id: "child", tool: .codex, isSubagent: true, parent: "main")
        let crossProvider = session(id: "cross", tool: .claudeCode, isSubagent: true, parent: "main")
        let orphan = session(id: "orphan", isSubagent: true)
        let workspace = AIProjectWorkspace(
            projectName: "project",
            projectPath: "/tmp/project",
            totalTokens: 40,
            totalCostUSD: 3,
            totalDurationSeconds: 10,
            sessionCount: 4,
            mainSessions: [active],
            subagentSessions: [linked, crossProvider, orphan]
        )
        XCTAssertEqual(workspace.id, "/tmp/project")
        XCTAssertEqual(workspace.totalCostUSD, 3)
        XCTAssertTrue(workspace.hasLiveActive)
        XCTAssertEqual(workspace.children(of: active).map(\.sessionId), ["child"])
        XCTAssertEqual(Set(workspace.unlinkedSubagentSessions.map(\.sessionId)), Set(["cross", "orphan"]))
        XCTAssertTrue(workspace.apiEquivalentEstimateIsComplete)

        let unlinked = AIProjectWorkspace(
            projectName: "Unlinked",
            projectPath: "",
            totalTokens: 0,
            actualCostUSD: nil,
            apiEquivalentEstimateUSD: nil,
            apiEquivalentEstimateIsComplete: false,
            totalDurationSeconds: 0,
            sessionCount: 0,
            mainSessions: [],
            subagentSessions: []
        )
        XCTAssertEqual(unlinked.id, "unlinked:Unlinked")
        XCTAssertFalse(unlinked.hasLiveActive)

        let project = AIProjectSummary(
            projectName: "p",
            sessionCount: 2,
            totalTokens: 10,
            totalCostUSD: 2,
            apiEquivalentEstimateUSD: 1,
            totalDurationSeconds: 20
        )
        XCTAssertEqual(project.id, "p")
        XCTAssertEqual(project.totalCostUSD, 2)

        let summary = AIAnalyticsSummary(
            activeSessions: [active],
            projectWorkspaces: [workspace],
            recentSessions: [linked],
            historySessions: [orphan],
            totalSessionsCount: 3,
            totalDurationSeconds: 30,
            totalTokensAllTime: 40,
            totalCostUSDAllTime: 0,
            totalTokensToday: 10,
            totalCostUSDToday: 0,
            topProjects: [project],
            allModelsUsed: active.modelsUsed,
            allTasksBreakdown: [],
            historyPersistenceStatus: .measured("ok")
        )
        XCTAssertEqual(summary.totalSessionsCount, 3)
        XCTAssertEqual(summary.historyPersistenceStatus.detail, "ok")
    }

    func testAnalyticsEngineFetchesFromConfiguredSourcesAndCachesSummary() throws {
        let root = try temporaryDirectory()
        let claudeDirectory = root.appendingPathComponent("claude", isDirectory: true)
        let antigravityDirectory = root.appendingPathComponent("brain", isDirectory: true)
        let codexDirectory = root.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: antigravityDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codexDirectory, withIntermediateDirectories: true)

        let engine = AISessionAnalyticsEngine(
            claudeParser: ClaudeCodeTelemetryParser(projectsDirectory: claudeDirectory),
            antigravityParser: AntigravityTelemetryParser(brainDirectory: antigravityDirectory),
            codexParser: CodexTelemetryParser(codexDirectory: codexDirectory),
            historyStore: AISessionHistoryStore(storeURL: root.appendingPathComponent("history.json")),
            codexRuntimeProbe: CodexRuntimeStatusProbe(databaseURL: root.appendingPathComponent("missing.sqlite")),
            processMonitor: ProcessMonitor()
        )

        let refreshed = engine.fetchSummary(forceRefresh: true)
        let cached = engine.fetchSummary()
        XCTAssertEqual(refreshed.totalSessionsCount, 0)
        XCTAssertEqual(cached.totalSessionsCount, refreshed.totalSessionsCount)
        XCTAssertFalse(refreshed.historyPersistenceStatus.detail.isEmpty)
    }

    func testHistoryStoreKeepsCurrentMeasuredUsageWhenRefreshingExistingRecord() throws {
        _ = AISessionHistoryStore()
        let root = try temporaryDirectory()
        let store = AISessionHistoryStore(storeURL: root.appendingPathComponent("history.json"))
        let previous = session(id: "merge-current", tokens: 10)
        _ = store.merge(current: [previous])
        let current = session(id: "merge-current", tokens: 30)
        let merged = try XCTUnwrap(store.merge(current: [current]).first)
        XCTAssertEqual(merged.tokenUsage.totalTokens, 30)
    }

    func testPricingCoversEveryRecognizedFamilyAndInvalidBucket() throws {
        let pricing = AIPricingCalculator()
        let recognized = [
            "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
            "gpt-5.4-mini", "gpt-5.4", "codex-auto-review", "gpt-5.3-codex",
            "gpt-5.2", "gpt-5", "gpt-5-2025-08-07",
            "claude-haiku-4.5", "claude-haiku-3-5", "claude-fable-5",
            "claude-mythos 5", "claude-sonnet-5", "claude-sonnet-4-6",
            "claude-opus-5", "claude-opus-4.8", "claude-opus-4-1",
            "deepseek-r1", "llama-3", "qwen3", "ollama"
        ]
        for model in recognized {
            XCTAssertNotNil(pricing.calculateCostUSD(model: model, inputTokens: 100, outputTokens: 20), model)
            XCTAssertNotNil(pricing.sourceDescription(for: model), model)
        }
        XCTAssertNil(pricing.sourceDescription(for: "unknown"))
        XCTAssertNil(pricing.calculateCostUSD(model: "unknown", inputTokens: 1, outputTokens: 1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: -1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: 0, cacheReadTokens: -1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: 0, cacheWriteTokens: -1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: 0, cacheWrite1hTokens: -1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: 0, thinkingTokens: -1))
        XCTAssertNil(pricing.calculateCostUSD(model: "gpt-5", inputTokens: 1, outputTokens: 0, cacheReadTokens: 2))
    }

    func testSummaryAggregatesAllLifecyclesModelsTasksAndUnlinkedProjects() throws {
        let modelA = AIModelUsage(modelName: "a", turnCount: 2, inputTokens: 100, outputTokens: 20, cacheReadTokens: 10, thinkingTokens: 3, estimatedCostUSD: 1)
        let modelB = AIModelUsage(modelName: "b", turnCount: 1, inputTokens: 20, outputTokens: 5, cacheReadTokens: 0, thinkingTokens: 0, estimatedCostUSD: 0.2)
        let task = AITaskCategoryUsage(category: .testing, callCount: 2, totalDurationMs: 200, tokenShare: 0, estimatedCostUSD: 0.5)
        let records = [
            session(id: "active", status: .thinking, age: 100_000, models: [modelA], tasks: [task]),
            session(id: "recent", status: .idle, age: 10, models: [modelB], tasks: [task]),
            session(id: "history", status: .aborted, age: 90_000, project: "Unlinked", path: "", cost: .unavailable),
            session(id: "child", status: .completed, age: 20, isSubagent: true, parent: "recent")
        ]
        let summary = AISessionAnalyticsEngine.buildSummary(
            sessions: records,
            now: now,
            historyPersistenceStatus: .measured("fixture")
        )
        XCTAssertEqual(summary.activeSessions.map(\.sessionId), ["active"])
        XCTAssertEqual(Set(summary.recentSessions.map(\.sessionId)), Set(["recent", "child"]))
        XCTAssertEqual(summary.historySessions.map(\.sessionId), ["history"])
        XCTAssertEqual(summary.totalSessionsCount, 4)
        XCTAssertEqual(summary.totalTokensAllTime, 40)
        XCTAssertEqual(summary.allModelsUsed.first?.modelName, "a")
        XCTAssertEqual(summary.allModelsUsed.first?.turnCount, 2)
        XCTAssertEqual(summary.allTasksBreakdown.first?.callCount, 4)
        XCTAssertEqual(summary.historyPersistenceStatus.detail, "fixture")
        XCTAssertEqual(summary.projectWorkspaces.count, 2)
        XCTAssertTrue(summary.projectWorkspaces.contains { $0.projectPath.isEmpty })
        XCTAssertEqual(summary.topProjects.first?.totalTokens, 30)
    }

    func testTreePresentationCoversTogglePagingSearchReconcileAndReveal() throws {
        let main = session(id: "main", status: .active)
        let children = (0..<5).map { session(id: "child-\($0)", status: .active, isSubagent: true, parent: "main") }
        let orphans = (0..<4).map { session(id: "orphan-\($0)", status: .active, isSubagent: true) }
        let workspace = AIProjectWorkspace(
            projectName: "project",
            projectPath: "/tmp/project",
            totalTokens: 100,
            totalDurationSeconds: 10,
            sessionCount: 10,
            mainSessions: [main] + (0..<4).map { session(id: "main-\($0)", status: .active) },
            subagentSessions: children + orphans
        )
        var state = AISessionTreePresentationState(lifecycle: .history, workspaces: [workspace], batchSize: 2)
        XCTAssertEqual(state.batchSize, 2)
        XCTAssertFalse(state.isWorkspaceExpanded(workspace))
        XCTAssertTrue(state.visibleMainSessions(in: workspace).isEmpty)
        XCTAssertEqual(state.remainingMainSessionCount(in: workspace), 0)
        XCTAssertTrue(state.visibleChildren(of: main, in: workspace).isEmpty)
        XCTAssertEqual(state.remainingChildCount(of: main, in: workspace), 0)
        XCTAssertTrue(state.visibleUnlinkedSessions(in: workspace).isEmpty)
        XCTAssertEqual(state.remainingUnlinkedSessionCount(in: workspace), 0)

        state.toggleWorkspace(workspace)
        XCTAssertEqual(state.visibleMainSessions(in: workspace).count, 2)
        XCTAssertEqual(state.remainingMainSessionCount(in: workspace), 3)
        state.loadMoreMainSessions(in: workspace)
        state.loadMoreMainSessions(in: workspace)
        XCTAssertEqual(state.visibleMainSessions(in: workspace).count, 5)
        state.toggleSession(main)
        XCTAssertEqual(state.visibleChildren(of: main, in: workspace).count, 2)
        XCTAssertEqual(state.remainingChildCount(of: main, in: workspace), 3)
        state.loadMoreChildren(of: main, in: workspace)
        state.loadMoreChildren(of: main, in: workspace)
        XCTAssertEqual(state.visibleChildren(of: main, in: workspace).count, 5)
        state.toggleUnlinkedSection(in: workspace)
        XCTAssertEqual(state.visibleUnlinkedSessions(in: workspace).count, 2)
        XCTAssertEqual(state.remainingUnlinkedSessionCount(in: workspace), 2)
        state.loadMoreUnlinkedSessions(in: workspace)
        XCTAssertEqual(state.visibleUnlinkedSessions(in: workspace).count, 4)

        state.toggleSession(main)
        state.toggleWorkspace(workspace)
        state.toggleUnlinkedSection(in: workspace)
        XCTAssertFalse(state.isWorkspaceExpanded(workspace))
        XCTAssertFalse(state.isSessionExpanded(main))
        XCTAssertFalse(state.isUnlinkedSectionExpanded(in: workspace))

        state.expandSearchResults(in: [workspace])
        XCTAssertTrue(state.isWorkspaceExpanded(workspace))
        XCTAssertTrue(state.isSessionExpanded(main))
        XCTAssertTrue(state.isUnlinkedSectionExpanded(in: workspace))

        state.reset(lifecycle: .recent, workspaces: [workspace])
        XCTAssertFalse(state.isWorkspaceExpanded(workspace))
        state.reveal(children[4], in: [workspace])
        XCTAssertTrue(state.isWorkspaceExpanded(workspace))
        XCTAssertTrue(state.isSessionExpanded(main))
        state.reset(lifecycle: .recent, workspaces: [workspace])
        state.reveal(orphans[0], in: [workspace])
        XCTAssertTrue(state.isUnlinkedSectionExpanded(in: workspace))
        state.reset(lifecycle: .recent, workspaces: [workspace])
        state.reveal(main, in: [workspace])
        XCTAssertTrue(state.isWorkspaceExpanded(workspace))
        state.reveal(session(id: "not-found"), in: [workspace])

        state.reset(lifecycle: .active, workspaces: [workspace])
        XCTAssertTrue(state.isWorkspaceExpanded(workspace))
        state.reconcile(lifecycle: .active, workspaces: [workspace])
        XCTAssertTrue(state.isSessionExpanded(main))
        state.reconcile(lifecycle: .history, workspaces: [])
        XCTAssertFalse(state.isWorkspaceExpanded(workspace))

        XCTAssertEqual(AISessionRefreshPolicy.interval(for: .active), 10)
        XCTAssertEqual(AISessionRefreshPolicy.interval(for: .recent), 30)
        XCTAssertNil(AISessionRefreshPolicy.interval(for: .history))
    }

    func testRuntimeReconcilerCoversAllCodexAndProcessStates() throws {
        let base = session(id: "codex", status: .unknown, project: "old", path: "/tmp/old")
        for (state, expected) in [
            (CodexThreadRuntimeState.inProgress, AISessionStatus.active),
            (.completed, .completed),
            (.failed, .aborted),
            (.interrupted, .aborted),
            (.cancelled, .aborted)
        ] {
            let value = try XCTUnwrap(AISessionRuntimeReconciler.reconcile(
                records: [base],
                codexStates: ["codex": state],
                codexExecutionCWDs: ["codex": "/tmp/new/.codex/worktrees/w1"],
                processes: [],
                now: now
            ).first)
            XCTAssertEqual(value.status, expected)
            XCTAssertEqual(value.projectPath, "/tmp/new")
            XCTAssertEqual(value.projectName, "new")
        }

        let exactEvidence = AIProviderProcessEvidence(
            toolType: .claudeCode,
            pid: 10,
            workingDirectory: "/tmp/project",
            sessionId: "exact",
            cpuPercentage: 12,
            memoryBytes: 34
        )
        let exact = session(id: "exact", tool: .claudeCode)
        let exactResult = try XCTUnwrap(AISessionRuntimeReconciler.reconcile(
            records: [exact], codexStates: [:], processes: [exactEvidence], now: now
        ).first)
        XCTAssertEqual(exactResult.status, .active)
        XCTAssertEqual(exactResult.livePID, 10)
        XCTAssertEqual(exactResult.liveCPU, 12)
        XCTAssertEqual(exactResult.liveMemoryBytes, 34)

        let process = AIProviderProcessEvidence(toolType: .claudeCode, pid: 20, workingDirectory: "/tmp/project/subdir")
        let fresh = AISessionRuntimeReconciler.reconcile(
            records: [session(id: "fresh", tool: .claudeCode, age: 10)],
            codexStates: [:], processes: [process], now: now
        )[0]
        XCTAssertEqual(fresh.status, .active)
        let idle = AISessionRuntimeReconciler.reconcile(
            records: [session(id: "idle", tool: .claudeCode, age: 100)],
            codexStates: [:], processes: [process], now: now
        )[0]
        XCTAssertEqual(idle.status, .idle)
        let old = AISessionRuntimeReconciler.reconcile(
            records: [session(id: "old", tool: .claudeCode, age: 90_000)],
            codexStates: [:], processes: [process], now: now
        )[0]
        XCTAssertEqual(old.status, .completed)
        let absent = AISessionRuntimeReconciler.reconcile(
            records: [session(id: "absent", tool: .claudeCode)],
            codexStates: [:], processes: [], now: now
        )[0]
        XCTAssertEqual(absent.status, .completed)

        let items = [
            ProcessItem(pid: 1, name: "c", workingDirectory: "/tmp/c", cpuPercentage: 1, memoryBytes: 2, aiContext: AIContextInfo(toolName: AIToolType.claudeCode.rawValue, sessionId: "c")),
            ProcessItem(pid: 2, name: "a", workingDirectory: "/tmp/a", aiContext: AIContextInfo(toolName: AIToolType.antigravity.rawValue)),
            ProcessItem(pid: 3, name: "x", workingDirectory: "/tmp/x", aiContext: AIContextInfo(toolName: AIToolType.codex.rawValue)),
            ProcessItem(pid: 4, name: "bad", workingDirectory: "", aiContext: AIContextInfo(toolName: "Unknown")),
            ProcessItem(pid: 5, name: "none")
        ]
        XCTAssertEqual(AISessionRuntimeReconciler.processEvidence(from: items).count, 3)
    }

    func testCoreMetricDiagnosticAndFanValueModelsCoverEveryPresentationBranch() {
        let core = CoreUsage(id: 1, coreNumber: 2, user: 10, system: 20, idle: 70, totalUsage: 30, isPerformanceCore: false)
        XCTAssertEqual(core.coreTypeName, "Efficiency")
        let cpu = CPUUsageSnapshot(totalUsage: 30, userUsage: 10, systemUsage: 20, idleUsage: 70, cores: [core], physicalCores: 1, logicalCores: 1, timestamp: now)
        XCTAssertEqual(cpu.cores.first?.id, 1)
        let memory = MemoryUsageSnapshot(totalPhysicalBytes: 100, activeBytes: 10, inactiveBytes: 20, wiredBytes: 30, compressedBytes: 5, freeBytes: 35, usedBytes: 45, usedPercentage: 45, swapTotalBytes: 10, swapUsedBytes: 2, pressureState: .warning, timestamp: now)
        XCTAssertEqual(memory.pressureState, .warning)

        XCTAssertEqual(ProcessCategory.allCases.map(\.iconName), ["app.badge.fill", "terminal.fill", "shippingbox.fill", "globe", "gearshape.2.fill", "lock.shield.fill"])
        let context = AIContextInfo(toolName: "Tool", modelName: "m", sessionId: "123456789", workspaceName: "p", taskSummary: "task")
        XCTAssertEqual(context.sessionShortId, "#123456")
        XCTAssertTrue(context.displayBadge.contains("🧠 m"))
        XCTAssertTrue(context.displayBadge.contains("🆔 #123456"))
        XCTAssertEqual(AIContextInfo(toolName: "Tool").displayBadge, "Tool")

        for (uptime, expected) in [
            (-1.0, "0 秒"), (30, "30 秒"), (120, "2 分鐘"),
            (3_660, "1 小時 1 分"), (90_000, "1 天 1 小時")
        ] {
            let item = ProcessItem(pid: 10, name: "n", uptimeSeconds: uptime)
            XCTAssertEqual(item.formattedUptime, expected)
            XCTAssertEqual(item.id, 10)
        }

        let docker = DockerContainerInfo(containerId: "id", name: "n", image: "i", cpuPercentage: 1, memoryUsage: "1MiB", memoryPercentage: 2, status: "Up", runningFor: "1h", command: "c")
        XCTAssertEqual(docker.id, "id")
        let volume = DiskVolumeInfo(name: "v", path: "/v", totalBytes: 100, freeBytes: 40)
        XCTAssertEqual(volume.id, "/v")
        XCTAssertEqual(volume.usedBytes, 60)
        XCTAssertEqual(volume.usedPercentage, 60)
        XCTAssertEqual(DiskVolumeInfo(name: "v", path: "/v", totalBytes: 0, freeBytes: 10).usedBytes, 0)
        _ = DiskIOSnapshot(readBytesPerSec: 1, writeBytesPerSec: 2, totalReadBytes: 3, totalWriteBytes: 4, timestamp: now)
        _ = NetworkIOSnapshot(uploadBytesPerSec: 1, downloadBytesPerSec: 2, totalUploadBytes: 3, totalDownloadBytes: 4, timestamp: now)
        _ = BatteryThermalSnapshot(hasBattery: true, isCharging: true, isACConnected: false, batteryPercentage: 80, maxCapacity: 90, designCapacity: 100, cycleCount: 10, healthPercentage: 90, batteryTemperatureCelsius: 35, powerWattage: 10, timeRemainingMinutes: 60, thermalState: .fair, timestamp: now)

        for severity in [LagSeverity.unknown, .smooth, .minor, .moderate, .severe] {
            XCTAssertFalse(severity.badgeColorHex.isEmpty)
            XCTAssertFalse(severity.systemIcon.isEmpty)
        }
        let cause = LagCauseItem(category: "c", title: "t", detail: "d", iconName: "i", isMajor: false)
        XCTAssertEqual(cause.id, "c-t")
        let action = RemediationAction(typeId: "a", title: "t", explanation: "e", buttonTitle: "b", iconName: "i", pid: 42, isDestructive: true)
        XCTAssertEqual(action.id, "a-42")
        let report = LagDiagnosticReport(healthScore: 90, severity: .smooth, summary: "s", causes: [cause], suggestedActions: [action], timestamp: now)
        XCTAssertEqual(report.healthScore, 90)

        let modes: [FanMode] = [.automatic, .quiet(), .balanced(), .maxCooling, .custom(rpm: 2_500)]
        XCTAssertEqual(modes.map(\.title).count, 5)
        XCTAssertEqual(modes.map(\.iconName).count, 5)
        XCTAssertEqual(modes.map(\.description).count, 5)
        XCTAssertEqual(modes.map(\.targetTemperatureCelsius), [nil, 75, 65, 50, nil])
        let fan = FanStatus(fanIndex: 2, name: "fan", currentRPM: 1, minRPM: 1, maxRPM: 3, targetRPM: 2, mode: .custom(rpm: 2))
        XCTAssertEqual(fan.id, 2)
    }
}
