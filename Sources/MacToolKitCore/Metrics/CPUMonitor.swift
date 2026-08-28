import Foundation
import Darwin

public final class CPUMonitor: @unchecked Sendable {
    private var previousCPUTicks: [processor_cpu_load_info] = []
    private let lock = NSLock()

    public init() {
        if let initial = sampleCPUTicks() {
            self.previousCPUTicks = initial
            usleep(60_000) // 60ms initial delta seed
        }
    }

    private func sampleCPUTicks() -> [processor_cpu_load_info]? {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var numCpuInfo: mach_msg_type_number_t = 0

        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCPUsU, &cpuInfo, &numCpuInfo)
        guard kr == KERN_SUCCESS, let cpuInfo = cpuInfo else {
            return nil
        }

        let count = Int(numCPUsU)
        let loads = cpuInfo.withMemoryRebound(to: processor_cpu_load_info.self, capacity: count) {
            Array(UnsafeBufferPointer(start: $0, count: count))
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo * UInt32(MemoryLayout<integer_t>.stride)))
        return loads
    }

    public func sample() -> CPUUsageSnapshot {
        lock.lock()
        defer { lock.unlock() }

        guard let currentTicks = sampleCPUTicks() else {
            return CPUUsageSnapshot()
        }

        guard !previousCPUTicks.isEmpty, previousCPUTicks.count == currentTicks.count else {
            previousCPUTicks = currentTicks
            usleep(50_000)
            guard let nextTicks = sampleCPUTicks(), nextTicks.count == currentTicks.count else {
                return CPUUsageSnapshot()
            }
            return computeSnapshot(previous: currentTicks, current: nextTicks)
        }

        let snapshot = computeSnapshot(previous: previousCPUTicks, current: currentTicks)
        previousCPUTicks = currentTicks
        return snapshot
    }

    private func computeSnapshot(previous: [processor_cpu_load_info], current: [processor_cpu_load_info]) -> CPUUsageSnapshot {
        var coreUsages: [CoreUsage] = []
        var totalUserDelta: Double = 0
        var totalSystemDelta: Double = 0
        var totalIdleDelta: Double = 0
        var totalTicksDelta: Double = 0

        for i in 0..<current.count {
            let cur = current[i]
            let prev = previous[i]

            let userDelta = Double(cur.cpu_ticks.0 >= prev.cpu_ticks.0 ? cur.cpu_ticks.0 - prev.cpu_ticks.0 : 0)
            let sysDelta = Double(cur.cpu_ticks.1 >= prev.cpu_ticks.1 ? cur.cpu_ticks.1 - prev.cpu_ticks.1 : 0)
            let idleDelta = Double(cur.cpu_ticks.2 >= prev.cpu_ticks.2 ? cur.cpu_ticks.2 - prev.cpu_ticks.2 : 0)
            let niceDelta = Double(cur.cpu_ticks.3 >= prev.cpu_ticks.3 ? cur.cpu_ticks.3 - prev.cpu_ticks.3 : 0)

            let coreTotal = userDelta + sysDelta + idleDelta + niceDelta
            let activeDelta = userDelta + sysDelta + niceDelta

            let coreUserPct = coreTotal > 0 ? (userDelta / coreTotal) * 100.0 : 0
            let coreSysPct = coreTotal > 0 ? (sysDelta / coreTotal) * 100.0 : 0
            let coreIdlePct = coreTotal > 0 ? (idleDelta / coreTotal) * 100.0 : 100.0
            let coreTotalPct = coreTotal > 0 ? (activeDelta / coreTotal) * 100.0 : 0

            totalUserDelta += userDelta
            totalSystemDelta += sysDelta
            totalIdleDelta += idleDelta
            totalTicksDelta += coreTotal

            coreUsages.append(CoreUsage(
                id: i,
                coreNumber: i + 1,
                user: coreUserPct,
                system: coreSysPct,
                idle: coreIdlePct,
                totalUsage: coreTotalPct,
                isPerformanceCore: i < (current.count > 8 ? current.count - 4 : current.count)
            ))
        }

        let overallTotal = totalTicksDelta > 0 ? ((totalUserDelta + totalSystemDelta) / totalTicksDelta) * 100.0 : 0
        let overallUser = totalTicksDelta > 0 ? (totalUserDelta / totalTicksDelta) * 100.0 : 0
        let overallSys = totalTicksDelta > 0 ? (totalSystemDelta / totalTicksDelta) * 100.0 : 0
        let overallIdle = totalTicksDelta > 0 ? (totalIdleDelta / totalTicksDelta) * 100.0 : 100.0

        return CPUUsageSnapshot(
            totalUsage: overallTotal,
            userUsage: overallUser,
            systemUsage: overallSys,
            idleUsage: overallIdle,
            cores: coreUsages,
            physicalCores: ProcessInfo.processInfo.activeProcessorCount,
            logicalCores: current.count,
            timestamp: Date()
        )
    }
}
