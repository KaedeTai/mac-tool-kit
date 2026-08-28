import XCTest
@testable import MacToolKitCore

final class LagDetectiveTests: XCTestCase {
    func testNormalWorkloadDiagnosis() {
        let detective = LagDetective()
        let cpu = CPUUsageSnapshot(totalUsage: 12.5)
        let memory = MemoryUsageSnapshot(
            totalPhysicalBytes: 32 * 1024 * 1024 * 1024,
            usedBytes: 12 * 1024 * 1024 * 1024,
            usedPercentage: 37.5,
            swapUsedBytes: 0,
            pressureState: .normal
        )
        let processes = [
            ProcessItem(pid: 100, name: "Finder", cpuPercentage: 1.2, memoryBytes: 200 * 1024 * 1024)
        ]
        let bt = BatteryThermalSnapshot(thermalState: .nominal)
        let dIO = DiskIOSnapshot(readBytesPerSec: 1024, writeBytesPerSec: 1024)

        let report = detective.diagnose(cpu: cpu, memory: memory, processes: processes, batteryThermal: bt, diskIO: dIO)
        XCTAssertGreaterThanOrEqual(report.healthScore, 85)
        XCTAssertEqual(report.severity, .smooth)
        XCTAssertTrue(report.suggestedActions.isEmpty)
    }

    func testHighCPUSpikeDiagnosis() {
        let detective = LagDetective()
        let cpu = CPUUsageSnapshot(totalUsage: 94.0)
        let memory = MemoryUsageSnapshot(totalPhysicalBytes: 32 * 1024 * 1024 * 1024, usedPercentage: 40.0)
        let runawayProcess = ProcessItem(pid: 9999, name: "RunawayBug", cpuPercentage: 92.0, memoryBytes: 500 * 1024 * 1024)
        let bt = BatteryThermalSnapshot(thermalState: .nominal)
        let dIO = DiskIOSnapshot()

        let report = detective.diagnose(cpu: cpu, memory: memory, processes: [runawayProcess], batteryThermal: bt, diskIO: dIO)
        XCTAssertLessThan(report.healthScore, 70)
        XCTAssertTrue(report.causes.contains(where: { $0.category.contains("CPU") || $0.category.contains("暴衝") }))
        XCTAssertTrue(report.suggestedActions.contains(where: { $0.pid == 9999 }))
    }

    func testMemoryExhaustionDiagnosis() {
        let detective = LagDetective()
        let cpu = CPUUsageSnapshot(totalUsage: 20.0)
        let memory = MemoryUsageSnapshot(
            totalPhysicalBytes: 16 * 1024 * 1024 * 1024,
            usedBytes: 15 * 1024 * 1024 * 1024,
            usedPercentage: 95.0,
            swapUsedBytes: 5 * 1024 * 1024 * 1024,
            pressureState: .critical
        )
        let bt = BatteryThermalSnapshot(thermalState: .nominal)
        let dIO = DiskIOSnapshot()

        let report = detective.diagnose(cpu: cpu, memory: memory, processes: [], batteryThermal: bt, diskIO: dIO)
        XCTAssertLessThan(report.healthScore, 60)
        XCTAssertTrue(report.suggestedActions.contains(where: { $0.typeId == "purge_memory" }))
    }

    func testThermalThrottlingDiagnosis() {
        let detective = LagDetective()
        let cpu = CPUUsageSnapshot(totalUsage: 25.0)
        let memory = MemoryUsageSnapshot(usedPercentage: 30.0)
        let bt = BatteryThermalSnapshot(thermalState: .serious)
        let dIO = DiskIOSnapshot()

        let report = detective.diagnose(cpu: cpu, memory: memory, processes: [], batteryThermal: bt, diskIO: dIO)
        XCTAssertTrue(report.suggestedActions.contains(where: { $0.typeId == "fan_max_cooling" }))
    }
}
