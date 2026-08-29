import Foundation
import IOKit
import IOKit.hidsystem

public enum ThermalSensorTarget: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case socPackage = "socPackage"
    case palmRest = "palmRest"
    case peakHotspot = "peakHotspot"
    case cpuPackage = "cpuPackage"
    case gpuCore = "gpuCore"
    case aneEngine = "aneEngine"
    case memoryRAM = "memoryRAM"
    case nvmeSSD = "nvmeSSD"
    case heatsink = "heatsink"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .socPackage: return "Apple Silicon SoC 晶片 (SoC Package)"
        case .palmRest: return "電池硬體感測器 (Battery Sensor)"
        case .peakHotspot: return "全機最熱元件 (Peak Hotspot)"
        case .cpuPackage: return "CPU 處理器核心 (CPU Package)"
        case .gpuCore: return "GPU 圖形渲染核心 (GPU Core)"
        case .aneEngine: return "ANE 神經網路引擎 (AI NPU)"
        case .memoryRAM: return "統一記憶體 (Unified RAM)"
        case .nvmeSSD: return "SSD 固態硬碟 (NVMe Storage)"
        case .heatsink: return "散熱鰭片與風道 (Heatsink)"
        }
    }

    public var shortName: String {
        switch self {
        case .socPackage: return "SoC 晶片"
        case .palmRest: return "電池感測器"
        case .peakHotspot: return "最熱點"
        case .cpuPackage: return "CPU 核心"
        case .gpuCore: return "GPU 核心"
        case .aneEngine: return "ANE 神經"
        case .memoryRAM: return "統一記憶體"
        case .nvmeSSD: return "SSD 硬碟"
        case .heatsink: return "散熱鰭片"
        }
    }

    public var iconName: String {
        switch self {
        case .socPackage: return "cpu.fill"
        case .palmRest: return "hand.raised.fill"
        case .peakHotspot: return "flame.fill"
        case .cpuPackage: return "cpu"
        case .gpuCore: return "gamecontroller.fill"
        case .aneEngine: return "brain.head.profile"
        case .memoryRAM: return "memorychip.fill"
        case .nvmeSSD: return "internaldrive.fill"
        case .heatsink: return "wind"
        }
    }

    public var defaultTargetTemp: Int {
        switch self {
        case .socPackage: return 60
        case .palmRest: return 34
        case .peakHotspot: return 60
        case .cpuPackage: return 65
        case .gpuCore: return 65
        case .aneEngine: return 60
        case .memoryRAM: return 55
        case .nvmeSSD: return 55
        case .heatsink: return 50
        }
    }

    public var description: String {
        switch self {
        case .socPackage: return "綜合 CPU、GPU、ANE 與記憶體控制器之 SoC 整合晶片整體熱度"
        case .palmRest: return "AppleSmartBattery 回報的電池溫度；不是掌托表面溫度，也不作為風扇閉迴路控制依據"
        case .peakHotspot: return "自動跟隨全機當前溫度最高的元件，提供全方位保護"
        case .cpuPackage: return "以 CPU 運算核心溫度為基準，適合大量程式編譯"
        case .gpuCore: return "以 GPU 圖形核心溫度為基準，適合 3D 渲染與遊戲"
        case .aneEngine: return "以 NPU 神經網路單元為基準，適合本機 AI 模型推理"
        case .memoryRAM: return "以 LPDDR5 記憶體晶粒溫度為基準"
        case .nvmeSSD: return "以高速 SSD 讀寫控制器溫度為基準"
        case .heatsink: return "以出風口散熱鰭片與導管溫度為基準"
        }
    }
}

public struct ComponentThermalPoint: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let temperatureCelsius: Double
    public let source: String

    public init(
        name: String,
        temperatureCelsius: Double,
        source: String
    ) {
        self.id = "\(source)::\(name)"
        self.name = name
        self.temperatureCelsius = temperatureCelsius
        self.source = source
    }
}

public struct ComponentThermalReading: Identifiable, Sendable {
    public let id: String
    public let target: ThermalSensorTarget
    public let name: String
    public let locationDescription: String
    public let temperatureCelsius: Double?
    public let iconName: String
    public let measuredPoints: [ComponentThermalPoint]
    public let isHotspot: Bool

    public init(
        target: ThermalSensorTarget,
        name: String,
        locationDescription: String,
        temperatureCelsius: Double?,
        iconName: String,
        measuredPoints: [ComponentThermalPoint] = [],
        isHotspot: Bool = false
    ) {
        self.id = target.rawValue
        self.target = target
        self.name = name
        self.locationDescription = locationDescription
        self.temperatureCelsius = temperatureCelsius
        self.iconName = iconName
        self.measuredPoints = measuredPoints
        self.isHotspot = isHotspot
    }
}

public enum ThermalSensorPresentation {
    /// The monitor keeps unsupported targets as explicit nil facts for diagnostics.
    /// Product UI should only render physical component cards backed by a current
    /// measurement. The peak card is a derived maximum of those same readings,
    /// so presenting it beside them would double-count a component source.
    public static func measuredPhysicalReadings(
        from readings: [ComponentThermalReading]
    ) -> [ComponentThermalReading] {
        readings.filter {
            $0.temperatureCelsius != nil && $0.target != .peakHotspot
        }
    }

    public static func measuredPointCount(
        from readings: [ComponentThermalReading]
    ) -> Int {
        measuredPhysicalReadings(from: readings).reduce(into: 0) { total, reading in
            total += reading.measuredPoints.isEmpty ? 1 : reading.measuredPoints.count
        }
    }
}

public struct SMCTemperatureSample: Equatable, Sendable {
    public let key: String
    public let valueCelsius: Double

    public init(key: String, valueCelsius: Double) {
        self.key = key
        self.valueCelsius = valueCelsius
    }
}

public struct HIDTemperatureSample: Equatable, Sendable {
    public let productName: String
    public let valueCelsius: Double

    public init(productName: String, valueCelsius: Double) {
        self.productName = productName
        self.valueCelsius = valueCelsius
    }
}

public enum SMCTemperatureReducer {
    /// Raw SMC keys such as Tp*, Tg*, and Tm* are real measurements, but Apple
    /// does not publish a product-independent component mapping for those key
    /// families. Keep them out of named CPU/GPU/RAM cards instead of guessing.
    public static func merge(
        samples: [SMCTemperatureSample],
        into base: [ComponentThermalReading]
    ) -> [ComponentThermalReading] {
        _ = samples
        return base
    }
}

public enum HIDTemperatureReducer {
    public static func merge(
        samples: [HIDTemperatureSample],
        into base: [ComponentThermalReading]
    ) -> [ComponentThermalReading] {
        let valid = samples.filter {
            !$0.productName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && $0.valueCelsius.isFinite
                && $0.valueCelsius > 0
                && $0.valueCelsius <= 150
        }
        var hottestByProduct: [String: Double] = [:]
        for sample in valid {
            hottestByProduct[sample.productName] = max(
                hottestByProduct[sample.productName] ?? -.infinity,
                sample.valueCelsius
            )
        }

        let soc = hottestByProduct.filter { name, _ in
            name.range(of: #"^PMU tdie[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let nand = hottestByProduct.filter { name, _ in
            name.range(of: #"^NAND CH[0-9]+ temp$"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        let battery = hottestByProduct.filter { name, _ in
            name.caseInsensitiveCompare("gas gauge battery") == .orderedSame
        }

        func points(
            from values: [String: Double],
            source: String
        ) -> [ComponentThermalPoint] {
            values
                .map { name, temperature in
                    ComponentThermalPoint(
                        name: name,
                        temperatureCelsius: temperature,
                        source: source
                    )
                }
                .sorted { lhs, rhs in
                    lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
        }

        var replacements: [ThermalSensorTarget: ComponentThermalReading] = [:]
        if let hottest = soc.values.max(), let coolest = soc.values.min() {
            replacements[.socPackage] = ComponentThermalReading(
                target: .socPackage,
                name: "SoC／PMU 晶粒最高值",
                locationDescription: String(
                    format: "Apple IOHID 私有感測服務 · %d 個具名實測點 · 範圍 %.1f–%.1f °C",
                    soc.count, coolest, hottest
                ),
                temperatureCelsius: hottest,
                iconName: ThermalSensorTarget.socPackage.iconName,
                measuredPoints: points(from: soc, source: "Apple IOHID")
            )
        }
        if let hottest = nand.values.max() {
            replacements[.nvmeSSD] = ComponentThermalReading(
                target: .nvmeSSD,
                name: "NAND 儲存裝置感測器",
                locationDescription: "Apple IOHID 私有感測服務 · \(nand.keys.sorted().joined(separator: ", "))",
                temperatureCelsius: hottest,
                iconName: ThermalSensorTarget.nvmeSSD.iconName,
                measuredPoints: points(from: nand, source: "Apple IOHID")
            )
        }
        if let hottest = battery.values.max() {
            replacements[.palmRest] = ComponentThermalReading(
                target: .palmRest,
                name: "電池硬體感測器",
                locationDescription: "Apple IOHID 私有感測服務 · gas gauge battery",
                temperatureCelsius: hottest,
                iconName: ThermalSensorTarget.palmRest.iconName,
                measuredPoints: points(from: battery, source: "Apple IOHID")
            )
        }

        var result = base.map { reading -> ComponentThermalReading in
            if reading.target == .palmRest, reading.temperatureCelsius != nil {
                return reading
            }
            return replacements[reading.target] ?? reading
        }
        let measured = result.compactMap(\.temperatureCelsius)
        if let peak = measured.max() {
            result.append(ComponentThermalReading(
                target: .peakHotspot,
                name: "可辨識感測來源最高值",
                locationDescription: "僅為目前可辨識來源的最高讀值，不是硬體危險門檻",
                temperatureCelsius: peak,
                iconName: ThermalSensorTarget.peakHotspot.iconName,
                isHotspot: true
            ))
        }
        return result
    }
}

private typealias MacDashboardHIDEventRef = CFTypeRef

@_silgen_name("IOHIDEventSystemClientCreate")
private func macDashboardIOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> IOHIDEventSystemClient?

@_silgen_name("IOHIDEventSystemClientSetMatching")
private func macDashboardIOHIDEventSystemClientSetMatching(
    _ client: IOHIDEventSystemClient,
    _ matching: CFDictionary
) -> Int32

@_silgen_name("IOHIDServiceClientCopyEvent")
private func macDashboardIOHIDServiceClientCopyEvent(
    _ service: IOHIDServiceClient,
    _ type: Int64,
    _ options: Int32,
    _ depth: Int64
) -> MacDashboardHIDEventRef?

@_silgen_name("IOHIDEventGetFloatValue")
private func macDashboardIOHIDEventGetFloatValue(
    _ event: MacDashboardHIDEventRef,
    _ field: UInt32
) -> Double

public struct IOHIDTemperatureMonitor: Sendable {
    public init() {}

    public func sample() -> [HIDTemperatureSample] {
        guard let client = macDashboardIOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return [] }
        let matching = ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary
        guard macDashboardIOHIDEventSystemClientSetMatching(client, matching) != 0,
              let services = IOHIDEventSystemClientCopyServices(client) as? [IOHIDServiceClient] else {
            return []
        }

        return services.compactMap { service in
            guard let product = IOHIDServiceClientCopyProperty(service, "Product" as CFString) as? String,
                  let event = macDashboardIOHIDServiceClientCopyEvent(service, 15, 0, 0) else {
                return nil
            }
            let value = macDashboardIOHIDEventGetFloatValue(event, 15 << 16)
            guard value.isFinite, value > 0, value <= 150 else { return nil }
            return HIDTemperatureSample(productName: product, valueCelsius: value)
        }
    }
}

public final class HardwareSensorMonitor: Sendable {
    private let batteryMonitor = BatteryThermalMonitor()
    private let hidMonitor = IOHIDTemperatureMonitor()

    public init() {}

    public func sampleAllComponents() -> [ComponentThermalReading] {
        let batterySnap = batteryMonitor.sample()
        let base = ThermalSensorTarget.allCases.filter { $0 != .peakHotspot }.map { target in
            let measured = target == .palmRest ? batterySnap.batteryTemperatureCelsius : nil
            let name = target == .palmRest ? "電池硬體感測器" : target.shortName
            let detail = target == .palmRest
                ? "AppleSmartBattery Temperature（不是掌托表面溫度）"
                : "目前沒有可驗證的硬體感測來源"
            let measuredPoints: [ComponentThermalPoint]
            if target == .palmRest, let measured {
                measuredPoints = [
                    ComponentThermalPoint(
                        name: "AppleSmartBattery Temperature",
                        temperatureCelsius: measured,
                        source: "AppleSmartBattery"
                    )
                ]
            } else {
                measuredPoints = []
            }
            return ComponentThermalReading(
                target: target,
                name: name,
                locationDescription: detail,
                temperatureCelsius: measured,
                iconName: target.iconName,
                measuredPoints: measuredPoints,
                isHotspot: false
            )
        }
        return HIDTemperatureReducer.merge(samples: hidMonitor.sample(), into: base)
    }
}
