import XCTest
@testable import MacToolKitCore

final class PrivilegedHelperManagerCoverageTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func increment() -> Int {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacDashboardHelperTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testInjectedManagerCoversInstallUninstallAndCapabilityOutcomes() async throws {
        let root = try temporaryDirectory()
        let bundled = root.appendingPathComponent("MacDashboardFanHelper")
        let tool = root.appendingPathComponent("installed-helper")
        let plist = root.appendingPathComponent("daemon.plist")
        let socket = root.appendingPathComponent("helper.sock")
        try Data("helper".utf8).write(to: bundled)
        try Data("installed".utf8).write(to: tool)
        try Data("plist".utf8).write(to: plist)

        let manager = PrivilegedHelperManager(
            helperToolPath: tool.path,
            daemonPlistPath: plist.path,
            socketPath: socket.path,
            bundledHelperLocator: { bundled },
            scriptExecutor: { _ in nil },
            pingProvider: { true },
            capabilityProvider: { .ready(fanCount: 2) },
            sleepProvider: { _ in }
        )
        XCTAssertTrue(manager.isInstalled())
        let isRunning = await manager.isRunning()
        let capability = await manager.capability()
        XCTAssertTrue(isRunning)
        XCTAssertEqual(capability, .ready(fanCount: 2))
        if case .success = await manager.installHelper() {} else { XCTFail("install should succeed") }
        if case .success = await manager.uninstallHelper() {} else { XCTFail("uninstall should succeed") }

        let failingScript = PrivilegedHelperManager(
            helperToolPath: tool.path,
            daemonPlistPath: plist.path,
            socketPath: socket.path,
            bundledHelperLocator: { bundled },
            scriptExecutor: { _ in "denied" },
            pingProvider: { false },
            capabilityProvider: { .unreachable },
            sleepProvider: { _ in }
        )
        let isFailingScriptRunning = await failingScript.isRunning()
        XCTAssertFalse(isFailingScriptRunning)
        if case .failure(let error) = await failingScript.installHelper() {
            XCTAssertEqual(error.message, "denied")
            XCTAssertEqual(error.errorDescription, "denied")
        } else { XCTFail("install should fail") }
        if case .failure(let error) = await failingScript.uninstallHelper() {
            XCTAssertEqual(error.message, "denied")
        } else { XCTFail("uninstall should fail") }

        let missing = PrivilegedHelperManager(
            helperToolPath: root.appendingPathComponent("missing-tool").path,
            daemonPlistPath: root.appendingPathComponent("missing-plist").path,
            socketPath: socket.path,
            bundledHelperLocator: { nil },
            scriptExecutor: { _ in nil },
            pingProvider: { false },
            capabilityProvider: { .unreachable },
            sleepProvider: { _ in }
        )
        XCTAssertFalse(missing.isInstalled())
        if case .failure(let error) = await missing.installHelper() {
            XCTAssertTrue(error.message.contains("找不到"))
        } else { XCTFail("missing helper should fail") }
    }

    func testInstallRequiresReadbackAndDefaultLocatorFindsBuildProduct() async throws {
        let root = try temporaryDirectory()
        let bundled = root.appendingPathComponent("MacDashboardFanHelper")
        try Data("helper".utf8).write(to: bundled)
        let counter = Counter()
        let manager = PrivilegedHelperManager(
            helperToolPath: root.appendingPathComponent("tool").path,
            daemonPlistPath: root.appendingPathComponent("plist").path,
            socketPath: root.appendingPathComponent("socket").path,
            bundledHelperLocator: { bundled },
            scriptExecutor: { _ in nil },
            pingProvider: { true },
            capabilityProvider: {
                counter.increment() < 15 ? .reachableWithoutReadback : .unreachable
            },
            sleepProvider: { _ in }
        )
        if case .failure(let error) = await manager.installHelper() {
            XCTAssertTrue(error.message.contains("未通過硬體讀回驗證"))
            XCTAssertTrue(error.message.contains("未連線"))
        } else { XCTFail("readback-free helper should fail") }

        XCTAssertNotNil(PrivilegedHelperManager.shared.locateBundledHelper())
    }
}
