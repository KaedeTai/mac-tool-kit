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
        XCTAssertFalse(report.suggestedActions.contains(where: { $0.typeId == "purge_memory" }))
        XCTAssertTrue(report.suggestedActions.contains(where: { $0.typeId == "open_memory_inspector" }))
        XCTAssertTrue(
            report.suggestedActions.contains(where: {
                $0.explanation.contains("inactive") && $0.explanation.contains("自動回收")
            })
        )
    }

    func testThermalThrottlingDiagnosis() {
        let detective = LagDetective()
        let cpu = CPUUsageSnapshot(totalUsage: 25.0)
        let memory = MemoryUsageSnapshot(usedPercentage: 30.0)
        let bt = BatteryThermalSnapshot(thermalState: .serious)
        let dIO = DiskIOSnapshot()

        let report = detective.diagnose(cpu: cpu, memory: memory, processes: [], batteryThermal: bt, diskIO: dIO)
        XCTAssertFalse(report.suggestedActions.contains(where: { $0.typeId == "fan_max_cooling" }))
    }

    func testMajorCauseCannotBeReportedAsSmooth() {
        let process = ProcessItem(pid: 9001, name: "Compiler", cpuPercentage: 55, memoryBytes: 100)
        let report = LagDetective().diagnose(
            cpu: CPUUsageSnapshot(totalUsage: 30),
            memory: MemoryUsageSnapshot(usedPercentage: 30),
            processes: [process],
            batteryThermal: BatteryThermalSnapshot(thermalState: .nominal),
            diskIO: DiskIOSnapshot()
        )
        XCTAssertNotEqual(report.severity, .smooth)
        XCTAssertTrue(report.summary.contains("主要"))
    }

    func testDashboardNeverRecommendsTerminatingItself() {
        let dashboard = ProcessItem(
            pid: 9002,
            name: "Mac Dashboard",
            rawName: "MacDashboardApp",
            bundleIdentifier: "com.peterting.mac-tool-kit.dashboard",
            cpuPercentage: 90,
            memoryBytes: 3 * 1024 * 1024 * 1024
        )
        let report = LagDetective().diagnose(
            cpu: CPUUsageSnapshot(totalUsage: 50),
            memory: MemoryUsageSnapshot(usedPercentage: 50),
            processes: [dashboard],
            batteryThermal: BatteryThermalSnapshot(thermalState: .nominal),
            diskIO: DiskIOSnapshot()
        )
        XCTAssertFalse(report.suggestedActions.contains { $0.pid == dashboard.pid })
    }

    func testMemoryActionReportsObservedUsageWithoutPromisingExactRelease() {
        let observedBytes = UInt64(4 * 1024 * 1024 * 1024)
        let process = ProcessItem(
            pid: 9003,
            name: "Docker Desktop",
            cpuPercentage: 5,
            memoryBytes: observedBytes
        )

        let report = LagDetective().diagnose(
            cpu: CPUUsageSnapshot(totalUsage: 20),
            memory: MemoryUsageSnapshot(usedPercentage: 85, pressureState: .warning),
            processes: [process],
            batteryThermal: BatteryThermalSnapshot(thermalState: .nominal),
            diskIO: DiskIOSnapshot()
        )

        guard let action = report.suggestedActions.first(where: { $0.pid == process.pid }) else {
            return XCTFail("missing memory-hog action")
        }
        XCTAssertEqual(action.buttonTitle, "結束應用（目前佔用 4.0 GiB）")
        XCTAssertTrue(action.explanation.contains("目前取樣"), action.explanation)
        XCTAssertTrue(action.explanation.contains("不保證"), action.explanation)
    }

    func testNormalMemoryPressureDoesNotClassifyLargeProcessAsLagCause() {
        let process = ProcessItem(
            pid: 9004,
            name: "Docker Desktop",
            cpuPercentage: 5,
            memoryBytes: 5 * 1024 * 1024 * 1024
        )

        let report = LagDetective().diagnose(
            cpu: CPUUsageSnapshot(totalUsage: 20),
            memory: MemoryUsageSnapshot(usedPercentage: 65, pressureState: .normal),
            processes: [process],
            batteryThermal: BatteryThermalSnapshot(thermalState: .nominal),
            diskIO: DiskIOSnapshot()
        )

        XCTAssertEqual(report.severity, .smooth)
        XCTAssertTrue(report.causes.isEmpty)
        XCTAssertTrue(report.suggestedActions.isEmpty)
    }
}
