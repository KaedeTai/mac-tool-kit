import Foundation

// MARK: - CPU Models
public struct CoreUsage: Identifiable, Sendable {
    public let id: Int
    public let coreNumber: Int
    public let user: Double
    public let system: Double
    public let idle: Double
    public let totalUsage: Double
    public let isPerformanceCore: Bool

    public init(id: Int, coreNumber: Int, user: Double, system: Double, idle: Double, totalUsage: Double, isPerformanceCore: Bool = true) {
        self.id = id
        self.coreNumber = coreNumber
        self.user = user
        self.system = system
        self.idle = idle
        self.totalUsage = totalUsage
        self.isPerformanceCore = isPerformanceCore
    }
}

public struct CPUUsageSnapshot: Sendable {
    public let totalUsage: Double
    public let userUsage: Double
    public let systemUsage: Double
    public let idleUsage: Double
    public let cores: [CoreUsage]
    public let physicalCores: Int
    public let logicalCores: Int
    public let timestamp: Date

    public init(totalUsage: Double = 0, userUsage: Double = 0, systemUsage: Double = 0, idleUsage: Double = 100, cores: [CoreUsage] = [], physicalCores: Int = 0, logicalCores: Int = 0, timestamp: Date = Date()) {
        self.totalUsage = totalUsage
        self.userUsage = userUsage
        self.systemUsage = systemUsage
        self.idleUsage = idleUsage
        self.cores = cores
        self.physicalCores = physicalCores
        self.logicalCores = logicalCores
        self.timestamp = timestamp
    }
}

// MARK: - Memory Models
public enum MemoryPressureState: String, Sendable {
    case normal = "正常 (Normal)"
    case warning = "偏高 (Warning)"
    case critical = "嚴重 (Critical)"
}

public struct MemoryUsageSnapshot: Sendable {
    public let totalPhysicalBytes: UInt64
    public let activeBytes: UInt64
    public let inactiveBytes: UInt64
    public let wiredBytes: UInt64
    public let compressedBytes: UInt64
    public let freeBytes: UInt64
    public let usedBytes: UInt64
    public let usedPercentage: Double
    public let swapTotalBytes: UInt64
    public let swapUsedBytes: UInt64
    public let pressureState: MemoryPressureState
    public let timestamp: Date

    public init(
        totalPhysicalBytes: UInt64 = 0,
        activeBytes: UInt64 = 0,
        inactiveBytes: UInt64 = 0,
        wiredBytes: UInt64 = 0,
        compressedBytes: UInt64 = 0,
        freeBytes: UInt64 = 0,
        usedBytes: UInt64 = 0,
        usedPercentage: Double = 0,
        swapTotalBytes: UInt64 = 0,
        swapUsedBytes: UInt64 = 0,
        pressureState: MemoryPressureState = .normal,
        timestamp: Date = Date()
    ) {
        self.totalPhysicalBytes = totalPhysicalBytes
        self.activeBytes = activeBytes
        self.inactiveBytes = inactiveBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.freeBytes = freeBytes
        self.usedBytes = usedBytes
        self.usedPercentage = usedPercentage
        self.swapTotalBytes = swapTotalBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressureState = pressureState
        self.timestamp = timestamp
    }
}

// MARK: - Process Models
public enum ProcessCategory: String, Sendable, CaseIterable {
    case generalApp = "應用程式"
    case developer = "開發工具 / 腳本"
    case container = "容器虛擬化"
    case browser = "瀏覽器分頁"
    case backgroundService = "後台進程"
    case system = "系統核心服務"

    public var iconName: String {
        switch self {
        case .generalApp: return "app.badge.fill"
        case .developer: return "terminal.fill"
        case .container: return "shippingbox.fill"
        case .browser: return "globe"
        case .backgroundService: return "gearshape.2.fill"
        case .system: return "lock.shield.fill"
        }
    }
}

public struct ProcessItem: Identifiable, Sendable {
    public var id: pid_t { pid }
    public let pid: pid_t
    public let name: String
    public let rawName: String
    public let category: ProcessCategory
    public let commandLine: String?
    public let workingDirectory: String?
    public let projectName: String?
    public let triggerAppName: String?
    public let triggerChain: [String]
    public let startedAt: Date?
    public let uptimeSeconds: TimeInterval
    public let bundleIdentifier: String?
    public let cpuPercentage: Double
    public let memoryBytes: UInt64
    public let memoryPercentage: Double
    public let threadCount: Int
    public let isUserApp: Bool
    public let terminationImpact: String
    public let parentAppName: String?

    public var formattedUptime: String {
        let total = Int(max(0, uptimeSeconds))
        if total < 60 {
            return "\(total) 秒"
        } else if total < 3600 {
            return "\(total / 60) 分鐘"
        } else if total < 86400 {
            let hours = total / 3600
            let mins = (total % 3600) / 60
            return "\(hours) 小時 \(mins) 分"
        } else {
            let days = total / 86400
            let hours = (total % 86400) / 3600
            return "\(days) 天 \(hours) 小時"
        }
    }

    public init(
        pid: pid_t,
        name: String,
        rawName: String? = nil,
        category: ProcessCategory = .generalApp,
        commandLine: String? = nil,
        workingDirectory: String? = nil,
        projectName: String? = nil,
        triggerAppName: String? = nil,
        triggerChain: [String] = [],
        startedAt: Date? = nil,
        uptimeSeconds: TimeInterval = 0,
        bundleIdentifier: String? = nil,
        cpuPercentage: Double = 0,
        memoryBytes: UInt64 = 0,
        memoryPercentage: Double = 0,
        threadCount: Int = 1,
        isUserApp: Bool = false,
        terminationImpact: String = "結束該行程以釋放系統資源",
        parentAppName: String? = nil
    ) {
        self.pid = pid
        self.name = name
        self.rawName = rawName ?? name
        self.category = category
        self.commandLine = commandLine
        self.workingDirectory = workingDirectory
        self.projectName = projectName
        self.triggerAppName = triggerAppName
        self.triggerChain = triggerChain
        self.startedAt = startedAt
        self.uptimeSeconds = uptimeSeconds
        self.bundleIdentifier = bundleIdentifier
        self.cpuPercentage = cpuPercentage
        self.memoryBytes = memoryBytes
        self.memoryPercentage = memoryPercentage
        self.threadCount = threadCount
        self.isUserApp = isUserApp
        self.terminationImpact = terminationImpact
        self.parentAppName = parentAppName
    }
}

// MARK: - Docker Models
public struct DockerContainerInfo: Identifiable, Sendable {
    public var id: String { containerId }
    public let containerId: String
    public let name: String
    public let image: String
    public let cpuPercentage: Double
    public let memoryUsage: String
    public let memoryPercentage: Double
    public let status: String
    public let runningFor: String
    public let command: String

    public init(
        containerId: String,
        name: String,
        image: String,
        cpuPercentage: Double = 0,
        memoryUsage: String = "0 MB",
        memoryPercentage: Double = 0,
        status: String = "running",
        runningFor: String = "",
        command: String = ""
    ) {
        self.containerId = containerId
        self.name = name
        self.image = image
        self.cpuPercentage = cpuPercentage
        self.memoryUsage = memoryUsage
        self.memoryPercentage = memoryPercentage
        self.status = status
        self.runningFor = runningFor
        self.command = command
    }
}

// MARK: - Disk Models
public struct DiskVolumeInfo: Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let totalBytes: UInt64
    public let freeBytes: UInt64
    public let usedBytes: UInt64
    public let usedPercentage: Double

    public init(name: String, path: String, totalBytes: UInt64, freeBytes: UInt64) {
        self.name = name
        self.path = path
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.usedBytes = totalBytes >= freeBytes ? totalBytes - freeBytes : 0
        self.usedPercentage = totalBytes > 0 ? (Double(self.usedBytes) / Double(totalBytes)) * 100.0 : 0
    }
}

public struct DiskIOSnapshot: Sendable {
    public let readBytesPerSec: Double
    public let writeBytesPerSec: Double
    public let totalReadBytes: UInt64
    public let totalWriteBytes: UInt64
    public let timestamp: Date

    public init(readBytesPerSec: Double = 0, writeBytesPerSec: Double = 0, totalReadBytes: UInt64 = 0, totalWriteBytes: UInt64 = 0, timestamp: Date = Date()) {
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
        self.totalReadBytes = totalReadBytes
        self.totalWriteBytes = totalWriteBytes
        self.timestamp = timestamp
    }
}

// MARK: - Network Models
public struct NetworkIOSnapshot: Sendable {
    public let uploadBytesPerSec: Double
    public let downloadBytesPerSec: Double
    public let totalUploadBytes: UInt64
    public let totalDownloadBytes: UInt64
    public let timestamp: Date

    public init(uploadBytesPerSec: Double = 0, downloadBytesPerSec: Double = 0, totalUploadBytes: UInt64 = 0, totalDownloadBytes: UInt64 = 0, timestamp: Date = Date()) {
        self.uploadBytesPerSec = uploadBytesPerSec
        self.downloadBytesPerSec = downloadBytesPerSec
        self.totalUploadBytes = totalUploadBytes
        self.totalDownloadBytes = totalDownloadBytes
        self.timestamp = timestamp
    }
}

// MARK: - Battery & Thermal Models
public enum SystemThermalState: String, Sendable {
    case nominal = "良好 (正常運作)"
    case fair = "微熱 (輕度負載)"
    case serious = "過熱 (開始降頻)"
    case critical = "危險 (極度高溫)"
}

public struct BatteryThermalSnapshot: Sendable {
    public let hasBattery: Bool
    public let isCharging: Bool
    public let isACConnected: Bool
    public let batteryPercentage: Int
    public let maxCapacity: Int
    public let designCapacity: Int
    public let cycleCount: Int
    public let healthPercentage: Double
    public let batteryTemperatureCelsius: Double
    public let powerWattage: Double
    public let timeRemainingMinutes: Int
    public let thermalState: SystemThermalState
    public let timestamp: Date

    public init(
        hasBattery: Bool = false,
        isCharging: Bool = false,
        isACConnected: Bool = true,
        batteryPercentage: Int = 100,
        maxCapacity: Int = 0,
        designCapacity: Int = 0,
        cycleCount: Int = 0,
        healthPercentage: Double = 100,
        batteryTemperatureCelsius: Double = 30.0,
        powerWattage: Double = 0,
        timeRemainingMinutes: Int = -1,
        thermalState: SystemThermalState = .nominal,
        timestamp: Date = Date()
    ) {
        self.hasBattery = hasBattery
        self.isCharging = isCharging
        self.isACConnected = isACConnected
        self.batteryPercentage = batteryPercentage
        self.maxCapacity = maxCapacity
        self.designCapacity = designCapacity
        self.cycleCount = cycleCount
        self.healthPercentage = healthPercentage
        self.batteryTemperatureCelsius = batteryTemperatureCelsius
        self.powerWattage = powerWattage
        self.timeRemainingMinutes = timeRemainingMinutes
        self.thermalState = thermalState
        self.timestamp = timestamp
    }
}
