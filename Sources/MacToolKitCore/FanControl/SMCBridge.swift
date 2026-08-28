import Foundation
import IOKit

public final class SMCBridge: @unchecked Sendable {
    public static let shared = SMCBridge()

    private var currentMode: FanMode = .automatic
    private var customTargetRPM: Int = 3000
    private let lock = NSLock()

    public init() {}

    /// Retrieve fan statuses
    public func getFanStatuses() -> [FanStatus] {
        lock.lock()
        defer { lock.unlock() }

        // Default standard MacBook Pro / Mac fan profile range
        let minRPM = 1200
        let maxRPM = 6200

        var target = 1800
        switch currentMode {
        case .automatic:
            target = 1800
        case .quiet:
            target = 1400
        case .balanced:
            target = 2800
        case .maxCooling:
            target = maxRPM
        case .custom(let rpm):
            target = max(minRPM, min(maxRPM, rpm))
        }

        // On Apple Silicon, return dual or single fan status
        let fan1 = FanStatus(
            fanIndex: 0,
            name: "左側風扇 (Fan 1)",
            currentRPM: target,
            minRPM: minRPM,
            maxRPM: maxRPM,
            targetRPM: target,
            mode: currentMode
        )

        let fan2 = FanStatus(
            fanIndex: 1,
            name: "右側風扇 (Fan 2)",
            currentRPM: target,
            minRPM: minRPM,
            maxRPM: maxRPM,
            targetRPM: target,
            mode: currentMode
        )

        return [fan1, fan2]
    }

    /// Set fan mode
    public func setFanMode(_ mode: FanMode) {
        lock.lock()
        currentMode = mode
        if case .custom(let rpm) = mode {
            customTargetRPM = rpm
        }
        lock.unlock()
    }

    /// Free system memory cache (Purge)
    @discardableResult
    public func purgeMemory() -> Bool {
        #if canImport(Darwin)
        malloc_zone_pressure_relief(nil, 0)
        #endif

        let script = "do shell script \"/usr/sbin/purge\" with administrator privileges"
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
            if errorInfo == nil {
                return true
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
