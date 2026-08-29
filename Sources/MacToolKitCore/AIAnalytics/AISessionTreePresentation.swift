import Foundation

public enum AISessionRefreshPolicy {
    /// Active data must remain responsive, Recent can refresh less often, and
    /// permanent History only changes when a new provider scan is requested.
    /// Avoid rebuilding thousands of retained rows on a timer while browsing it.
    public static func interval(for lifecycle: AISessionLifecycle) -> TimeInterval? {
        switch lifecycle {
        case .active: return 10
        case .recent: return 30
        case .history: return nil
        }
    }
}

/// A single source of truth for whether an API-equivalent estimate may be
/// rendered. The user-facing toggle must apply consistently to both the tree
/// rows and the selected-session evidence panel.
public enum AISessionCostPresentation {
    public static func shouldDisplay(
        _ cost: AICostValue,
        estimatesEnabled: Bool
    ) -> Bool {
        estimatesEnabled
            && cost.kind == .apiEquivalentEstimate
            && cost.amountUSD != nil
    }
}

/// UI-independent disclosure and paging state for the project/session tree.
///
/// History can contain thousands of retained records. Keeping this policy in
/// Core makes it testable and prevents a SwiftUI render from eagerly creating
/// every row in a large project.
public struct AISessionTreePresentationState: Sendable {
    public let batchSize: Int

    private var expandedWorkspaceIDs: Set<String>
    private var expandedSessionIDs: Set<String>
    private var expandedUnlinkedWorkspaceIDs: Set<String>
    private var mainSessionLimits: [String: Int]
    private var childSessionLimits: [String: Int]
    private var unlinkedSessionLimits: [String: Int]

    public init(
        lifecycle: AISessionLifecycle,
        workspaces: [AIProjectWorkspace],
        batchSize: Int = 40
    ) {
        self.batchSize = max(1, batchSize)
        self.expandedWorkspaceIDs = []
        self.expandedSessionIDs = []
        self.expandedUnlinkedWorkspaceIDs = []
        self.mainSessionLimits = [:]
        self.childSessionLimits = [:]
        self.unlinkedSessionLimits = [:]
        reset(lifecycle: lifecycle, workspaces: workspaces)
    }

    public mutating func reset(
        lifecycle: AISessionLifecycle,
        workspaces: [AIProjectWorkspace]
    ) {
        expandedWorkspaceIDs.removeAll(keepingCapacity: true)
        expandedSessionIDs.removeAll(keepingCapacity: true)
        expandedUnlinkedWorkspaceIDs.removeAll(keepingCapacity: true)
        mainSessionLimits.removeAll(keepingCapacity: true)
        childSessionLimits.removeAll(keepingCapacity: true)
        unlinkedSessionLimits.removeAll(keepingCapacity: true)

        guard lifecycle == .active else { return }
        for workspace in workspaces {
            expandedWorkspaceIDs.insert(workspace.id)
            for session in workspace.mainSessions where !workspace.children(of: session).isEmpty {
                expandedSessionIDs.insert(session.id)
            }
            if !workspace.unlinkedSubagentSessions.isEmpty {
                expandedUnlinkedWorkspaceIDs.insert(workspace.id)
            }
        }
    }

    public mutating func reconcile(
        lifecycle: AISessionLifecycle,
        workspaces: [AIProjectWorkspace]
    ) {
        let workspaceIDs = Set(workspaces.map(\.id))
        let sessionIDs = Set(workspaces.flatMap { $0.mainSessions.map(\.id) })
        expandedWorkspaceIDs.formIntersection(workspaceIDs)
        expandedSessionIDs.formIntersection(sessionIDs)
        expandedUnlinkedWorkspaceIDs.formIntersection(workspaceIDs)

        guard lifecycle == .active else { return }
        for workspace in workspaces {
            expandedWorkspaceIDs.insert(workspace.id)
            for session in workspace.mainSessions where !workspace.children(of: session).isEmpty {
                expandedSessionIDs.insert(session.id)
            }
            if !workspace.unlinkedSubagentSessions.isEmpty {
                expandedUnlinkedWorkspaceIDs.insert(workspace.id)
            }
        }
    }

    public mutating func expandSearchResults(in workspaces: [AIProjectWorkspace]) {
        for workspace in workspaces {
            expandedWorkspaceIDs.insert(workspace.id)
            for session in workspace.mainSessions where !workspace.children(of: session).isEmpty {
                expandedSessionIDs.insert(session.id)
            }
            if !workspace.unlinkedSubagentSessions.isEmpty {
                expandedUnlinkedWorkspaceIDs.insert(workspace.id)
            }
        }
    }

    /// Reveals only the branch that contains the selected record. Recent data
    /// stays bounded, but the detail panel can no longer point at a child that
    /// is invisible behind two collapsed disclosure levels.
    public mutating func reveal(
        _ selectedSession: AISessionRecord,
        in workspaces: [AIProjectWorkspace]
    ) {
        guard let workspace = workspaces.first(where: { workspace in
            workspace.mainSessions.contains { $0.id == selectedSession.id }
                || workspace.subagentSessions.contains { $0.id == selectedSession.id }
        }) else { return }

        expandedWorkspaceIDs.insert(workspace.id)
        guard selectedSession.isSubagent else { return }

        if let parent = workspace.mainSessions.first(where: { main in
            workspace.children(of: main).contains { $0.id == selectedSession.id }
        }) {
            expandedSessionIDs.insert(parent.id)
        } else if workspace.unlinkedSubagentSessions.contains(where: { $0.id == selectedSession.id }) {
            expandedUnlinkedWorkspaceIDs.insert(workspace.id)
        }
    }

    public func isWorkspaceExpanded(_ workspace: AIProjectWorkspace) -> Bool {
        expandedWorkspaceIDs.contains(workspace.id)
    }

    public mutating func toggleWorkspace(_ workspace: AIProjectWorkspace) {
        if expandedWorkspaceIDs.contains(workspace.id) {
            expandedWorkspaceIDs.remove(workspace.id)
        } else {
            expandedWorkspaceIDs.insert(workspace.id)
        }
    }

    public func isSessionExpanded(_ session: AISessionRecord) -> Bool {
        expandedSessionIDs.contains(session.id)
    }

    public mutating func toggleSession(_ session: AISessionRecord) {
        if expandedSessionIDs.contains(session.id) {
            expandedSessionIDs.remove(session.id)
        } else {
            expandedSessionIDs.insert(session.id)
        }
    }

    public func isUnlinkedSectionExpanded(in workspace: AIProjectWorkspace) -> Bool {
        expandedUnlinkedWorkspaceIDs.contains(workspace.id)
    }

    public mutating func toggleUnlinkedSection(in workspace: AIProjectWorkspace) {
        if expandedUnlinkedWorkspaceIDs.contains(workspace.id) {
            expandedUnlinkedWorkspaceIDs.remove(workspace.id)
        } else {
            expandedUnlinkedWorkspaceIDs.insert(workspace.id)
        }
    }

    public func visibleMainSessions(in workspace: AIProjectWorkspace) -> [AISessionRecord] {
        guard isWorkspaceExpanded(workspace) else { return [] }
        return Array(workspace.mainSessions.prefix(mainSessionLimit(in: workspace)))
    }

    public func remainingMainSessionCount(in workspace: AIProjectWorkspace) -> Int {
        guard isWorkspaceExpanded(workspace) else { return 0 }
        return max(0, workspace.mainSessions.count - visibleMainSessions(in: workspace).count)
    }

    public mutating func loadMoreMainSessions(in workspace: AIProjectWorkspace) {
        mainSessionLimits[workspace.id] = min(
            workspace.mainSessions.count,
            mainSessionLimit(in: workspace) + batchSize
        )
    }

    public func visibleChildren(
        of mainSession: AISessionRecord,
        in workspace: AIProjectWorkspace
    ) -> [AISessionRecord] {
        guard isWorkspaceExpanded(workspace), isSessionExpanded(mainSession) else { return [] }
        let children = workspace.children(of: mainSession)
        return Array(children.prefix(childSessionLimit(for: mainSession, in: workspace)))
    }

    public func remainingChildCount(
        of mainSession: AISessionRecord,
        in workspace: AIProjectWorkspace
    ) -> Int {
        guard isWorkspaceExpanded(workspace), isSessionExpanded(mainSession) else { return 0 }
        return max(0, workspace.children(of: mainSession).count - visibleChildren(of: mainSession, in: workspace).count)
    }

    public mutating func loadMoreChildren(
        of mainSession: AISessionRecord,
        in workspace: AIProjectWorkspace
    ) {
        let key = childLimitKey(for: mainSession, in: workspace)
        childSessionLimits[key] = min(
            workspace.children(of: mainSession).count,
            childSessionLimit(for: mainSession, in: workspace) + batchSize
        )
    }

    public func visibleUnlinkedSessions(in workspace: AIProjectWorkspace) -> [AISessionRecord] {
        guard isWorkspaceExpanded(workspace), isUnlinkedSectionExpanded(in: workspace) else { return [] }
        return Array(workspace.unlinkedSubagentSessions.prefix(unlinkedSessionLimit(in: workspace)))
    }

    public func remainingUnlinkedSessionCount(in workspace: AIProjectWorkspace) -> Int {
        guard isWorkspaceExpanded(workspace), isUnlinkedSectionExpanded(in: workspace) else { return 0 }
        return max(0, workspace.unlinkedSubagentSessions.count - visibleUnlinkedSessions(in: workspace).count)
    }

    public mutating func loadMoreUnlinkedSessions(in workspace: AIProjectWorkspace) {
        unlinkedSessionLimits[workspace.id] = min(
            workspace.unlinkedSubagentSessions.count,
            unlinkedSessionLimit(in: workspace) + batchSize
        )
    }

    private func mainSessionLimit(in workspace: AIProjectWorkspace) -> Int {
        mainSessionLimits[workspace.id] ?? batchSize
    }

    private func childSessionLimit(
        for mainSession: AISessionRecord,
        in workspace: AIProjectWorkspace
    ) -> Int {
        childSessionLimits[childLimitKey(for: mainSession, in: workspace)] ?? batchSize
    }

    private func unlinkedSessionLimit(in workspace: AIProjectWorkspace) -> Int {
        unlinkedSessionLimits[workspace.id] ?? batchSize
    }

    private func childLimitKey(
        for mainSession: AISessionRecord,
        in workspace: AIProjectWorkspace
    ) -> String {
        "\(workspace.id)::\(mainSession.id)"
    }

}
