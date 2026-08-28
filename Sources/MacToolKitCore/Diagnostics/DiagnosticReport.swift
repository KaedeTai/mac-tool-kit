import Foundation
import Darwin

public enum LagSeverity: String, Sendable {
    case smooth = "系統極致順暢 (Smooth)"
    case minor = "輕微負載 (Normal Load)"
    case moderate = "中度遲滯 (Moderate Lag)"
    case severe = "嚴重卡頓 (Severe Bottleneck)"

    public var badgeColorHex: String {
        switch self {
        case .smooth: return "#34C759"     // Green
        case .minor: return "#30B0C7"      // Cyan/Teal
        case .moderate: return "#FF9500"   // Orange
        case .severe: return "#FF3B30"     // Red
        }
    }

    public var systemIcon: String {
        switch self {
        case .smooth: return "checkmark.seal.fill"
        case .minor: return "info.circle.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .severe: return "xmark.octagon.fill"
        }
    }
}

public struct LagCauseItem: Identifiable, Sendable {
    public var id: String { "\(category)-\(title)" }
    public let category: String
    public let title: String
    public let detail: String
    public let iconName: String
    public let isMajor: Bool

    public init(category: String, title: String, detail: String, iconName: String, isMajor: Bool = true) {
        self.category = category
        self.title = title
        self.detail = detail
        self.iconName = iconName
        self.isMajor = isMajor
    }
}

public struct RemediationAction: Identifiable, Sendable {
    public var id: String { "\(typeId)-\(pid ?? 0)" }
    public let typeId: String
    public let title: String
    public let explanation: String
    public let buttonTitle: String
    public let iconName: String
    public let pid: pid_t?
    public let isDestructive: Bool

    public init(typeId: String, title: String, explanation: String, buttonTitle: String, iconName: String, pid: pid_t? = nil, isDestructive: Bool = false) {
        self.typeId = typeId
        self.title = title
        self.explanation = explanation
        self.buttonTitle = buttonTitle
        self.iconName = iconName
        self.pid = pid
        self.isDestructive = isDestructive
    }
}

public struct LagDiagnosticReport: Sendable {
    public let healthScore: Int // 0 to 100
    public let severity: LagSeverity
    public let summary: String
    public let causes: [LagCauseItem]
    public let suggestedActions: [RemediationAction]
    public let timestamp: Date

    public init(
        healthScore: Int = 100,
        severity: LagSeverity = .smooth,
        summary: String = "系統運作良好，未發現異常資源佔用或延遲瓶頸。",
        causes: [LagCauseItem] = [],
        suggestedActions: [RemediationAction] = [],
        timestamp: Date = Date()
    ) {
        self.healthScore = healthScore
        self.severity = severity
        self.summary = summary
        self.causes = causes
        self.suggestedActions = suggestedActions
        self.timestamp = timestamp
    }
}
