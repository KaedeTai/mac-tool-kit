import XCTest
@testable import MacToolKitCore

final class MetricsTests: XCTestCase {
    func testCPUMonitorSampling() {
        let monitor = CPUMonitor()
        let snapshot1 = monitor.sample()
        XCTAssertGreaterThan(snapshot1.logicalCores, 0)
        XCTAssertEqual(snapshot1.cores.count, snapshot1.logicalCores)

        Thread.sleep(forTimeInterval: 0.05)
        let snapshot2 = monitor.sample()
        XCTAssertGreaterThanOrEqual(snapshot2.totalUsage, 0.0)
        XCTAssertLessThanOrEqual(snapshot2.totalUsage, 100.0)
    }

    func testMemoryMonitorSampling() {
        let monitor = MemoryMonitor()
        let snapshot = monitor.sample()

        XCTAssertGreaterThan(snapshot.totalPhysicalBytes, 0)
        XCTAssertGreaterThan(snapshot.activeBytes, 0)
        XCTAssertGreaterThanOrEqual(snapshot.usedPercentage, 0.0)
        XCTAssertLessThanOrEqual(snapshot.usedPercentage, 100.0)
    }

    func testProcessMonitorSampling() {
        let monitor = ProcessMonitor()
        let processes = monitor.sampleProcesses(limit: 20)

        XCTAssertFalse(processes.isEmpty)
        XCTAssertTrue(processes.contains(where: { $0.pid > 0 }))
    }

    func testDiskMonitorSampling() {
        let monitor = DiskMonitor()
        let volumes = monitor.sampleVolumes()
        XCTAssertFalse(volumes.isEmpty)

        let io = monitor.sampleIO()
        XCTAssertGreaterThanOrEqual(io.readBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(io.writeBytesPerSec, 0)
    }

    func testNetworkMonitorSampling() {
        let monitor = NetworkMonitor()
        let net = monitor.sample()
        XCTAssertGreaterThanOrEqual(net.uploadBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(net.downloadBytesPerSec, 0)
    }

    func testBatteryThermalMonitor() {
        let monitor = BatteryThermalMonitor()
        let snapshot = monitor.sample()
        XCTAssertNotNil(snapshot.thermalState)
    }
}
