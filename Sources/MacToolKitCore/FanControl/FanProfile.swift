import Foundation

public enum FanMode: Hashable, Sendable {
    case automatic
    case quiet(targetTemp: Int = 75)
    case balanced(targetTemp: Int = 65)
    case maxCooling
    case custom(rpm: Int)

    public var title: String {
        switch self {
        case .automatic: return "原廠動態 (Auto)"
        case .quiet: return "靜音策略 (目標 75°C)"
        case .balanced: return "智慧溫控 (目標 65°C)"
        case .maxCooling: return "極限壓溫 (Max Turbo)"
        case .custom(let rpm): return "自訂轉速 (\(rpm) RPM)"
        }
    }

    public var targetTemperatureCelsius: Int? {
        switch self {
        case .automatic: return nil
        case .quiet(let temp): return temp
        case .balanced(let temp): return temp
        case .maxCooling: return 50
        case .custom: return nil
        }
    }

    public var iconName: String {
        switch self {
        case .automatic: return "gearshape.2.fill"
        case .quiet: return "wind"
        case .balanced: return "gauge.with.needle.fill"
        case .maxCooling: return "snowflake"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var description: String {
        switch self {
        case .automatic: return "由 macOS 系統根據晶片負載自動溫控，低負載時靜音，高溫時升速"
        case .quiet: return "晶片未達 75°C 前維持最低轉速，享受極致安靜；高於 75°C 漸進調速"
        case .balanced: return "以維持晶片在 65°C 內為目標，中等負載提早升速以防止過熱降頻"
        case .maxCooling: return "全速運轉提供最大散熱風量，快速壓制高負載溫度"
        case .custom(let rpm): return "手動固定風扇轉速至 \(rpm) RPM"
        }
    }
}

public struct FanStatus: Identifiable, Sendable {
    public var id: Int { fanIndex }
    public let fanIndex: Int
    public let name: String
    public let currentRPM: Int
    public let minRPM: Int
    public let maxRPM: Int
    public let targetRPM: Int
    public let mode: FanMode

    public init(
        fanIndex: Int = 0,
        name: String = "主散熱風扇",
        currentRPM: Int = 1800,
        minRPM: Int = 1200,
        maxRPM: Int = 6000,
        targetRPM: Int = 1800,
        mode: FanMode = .automatic
    ) {
        self.fanIndex = fanIndex
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
        self.targetRPM = targetRPM
        self.mode = mode
    }
}
