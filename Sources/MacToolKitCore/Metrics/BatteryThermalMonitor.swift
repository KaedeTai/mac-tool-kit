import Foundation
import IOKit
import IOKit.ps

public final class BatteryThermalMonitor: Sendable {
    public init() {}

    public func sample() -> BatteryThermalSnapshot {
        return autoreleasepool {
            // Thermal State
            let thermalState: SystemThermalState
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: thermalState = .nominal
            case .fair: thermalState = .fair
            case .serious: thermalState = .serious
            case .critical: thermalState = .critical
            @unknown default: thermalState = .nominal
            }

            var hasBattery = false
            var isCharging = false
            var isACConnected = true
            var batteryPct = 100
            var maxCapacity = 0
            var designCapacity = 0
            var cycleCount = 0
            var healthPct: Double = 100.0
            var batteryTempCelsius: Double = 32.0
            var powerWattage: Double = 0.0
            var timeRemainingMins = -1

            // 1. Read IOPS info
            if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
               let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
               !list.isEmpty {
                hasBattery = true
                for ps in list {
                    if let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] {
                        if let cur = desc[kIOPSCurrentCapacityKey] as? Int {
                            batteryPct = cur
                        }
                        if let charging = desc[kIOPSIsChargingKey] as? Bool {
                            isCharging = charging
                        }
                        if let state = desc[kIOPSPowerSourceStateKey] as? String {
                            isACConnected = (state == kIOPSACPowerValue)
                        }
                        if let time = desc[kIOPSTimeToEmptyKey] as? Int {
                            timeRemainingMins = time
                        }
                    }
                }
            }

            // 2. Read AppleSmartBattery for Hardware Details
            var iterator: io_iterator_t = 0
            if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS {
                var entry = IOIteratorNext(iterator)
                while entry != 0 {
                    var props: Unmanaged<CFMutableDictionary>?
                    if IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                       let dict = props?.takeRetainedValue() as? [String: Any] {
                        hasBattery = true
                        if let cycles = dict["CycleCount"] as? Int {
                            cycleCount = cycles
                        }
                        if let design = dict["DesignCapacity"] as? Int {
                            designCapacity = design
                        }
                        if let maxCap = (dict["AppleRawMaxCapacity"] ?? dict["MaxCapacity"]) as? Int {
                            maxCapacity = maxCap
                        }
                        if designCapacity > 0 && maxCapacity > 0 {
                            healthPct = min(100.0, (Double(maxCapacity) / Double(designCapacity)) * 100.0)
                        }
                        if let tempK10 = dict["Temperature"] as? Double {
                            batteryTempCelsius = (tempK10 / 10.0) - 273.15
                        }
                        if let amp = dict["Amperage"] as? Double, let volt = dict["Voltage"] as? Double {
                            let battWatt = abs(amp * volt) / 1_000_000.0
                            if battWatt > 0.1 {
                                powerWattage = battWatt
                            } else if isACConnected {
                                let cpuPct = CPUMonitor().sample().totalUsage
                                powerWattage = 5.2 + (cpuPct * 0.35)
                            } else {
                                powerWattage = 0.0
                            }
                        }
                    }
                    IOObjectRelease(entry)
                    entry = IOIteratorNext(iterator)
                }
                IOObjectRelease(iterator)
            }

            return BatteryThermalSnapshot(
                hasBattery: hasBattery,
                isCharging: isCharging,
                isACConnected: isACConnected,
                batteryPercentage: batteryPct,
                maxCapacity: maxCapacity,
                designCapacity: designCapacity,
                cycleCount: cycleCount,
                healthPercentage: healthPct,
                batteryTemperatureCelsius: batteryTempCelsius,
                powerWattage: powerWattage,
                timeRemainingMinutes: timeRemainingMins,
                thermalState: thermalState,
                timestamp: Date()
            )
        }
    }
}
