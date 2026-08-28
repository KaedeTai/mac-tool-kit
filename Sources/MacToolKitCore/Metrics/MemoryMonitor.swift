import Foundation
import Darwin

public final class MemoryMonitor: Sendable {
    public init() {}

    public func sample() -> MemoryUsageSnapshot {
        let totalPhysical = ProcessInfo.processInfo.physicalMemory

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStats = vm_statistics64()

        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard kr == KERN_SUCCESS else {
            return MemoryUsageSnapshot(totalPhysicalBytes: totalPhysical)
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let inactive = UInt64(vmStats.inactive_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let free = UInt64(vmStats.free_count) * pageSize

        // Real used memory on macOS is active + wired + compressed
        let used = active + wired + compressed
        let usedPercentage = totalPhysical > 0 ? (Double(used) / Double(totalPhysical)) * 100.0 : 0

        // Swap memory via sysctl
        var swap = xsw_usage()
        var swapSize = MemoryLayout<xsw_usage>.size
        var swapTotal: UInt64 = 0
        var swapUsed: UInt64 = 0

        if sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 {
            swapTotal = UInt64(swap.xsu_total)
            swapUsed = UInt64(swap.xsu_used)
        }

        // Determine Memory Pressure state
        let pressureState: MemoryPressureState
        let pressureRatio = Double(used) / Double(totalPhysical)
        if pressureRatio > 0.88 || swapUsed > 4 * 1024 * 1024 * 1024 {
            pressureState = .critical
        } else if pressureRatio > 0.75 || swapUsed > 1024 * 1024 * 1024 {
            pressureState = .warning
        } else {
            pressureState = .normal
        }

        return MemoryUsageSnapshot(
            totalPhysicalBytes: totalPhysical,
            activeBytes: active,
            inactiveBytes: inactive,
            wiredBytes: wired,
            compressedBytes: compressed,
            freeBytes: free,
            usedBytes: used,
            usedPercentage: min(100.0, max(0.0, usedPercentage)),
            swapTotalBytes: swapTotal,
            swapUsedBytes: swapUsed,
            pressureState: pressureState,
            timestamp: Date()
        )
    }
}
