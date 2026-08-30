import XCTest
@testable import MacToolKitCore

final class MetricsTests: XCTestCase {
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0

        func increment() {
            lock.lock()
            value += 1
            lock.unlock()
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

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

        Thread.sleep(forTimeInterval: 0.08)
        let secondSample = monitor.sampleProcesses(limit: nil)
        XCTAssertFalse(secondSample.isEmpty)
        XCTAssertFalse(monitor.terminateProcess(pid: 2_000_000_000))
        XCTAssertFalse(monitor.lowerPriority(pid: 2_000_000_000))

        _ = monitor.sampleDockerContainers()
        _ = monitor.sampleDockerContainers()
    }

    func testDiskMonitorSampling() {
        let monitor = DiskMonitor()
        let volumes = monitor.sampleVolumes()
        XCTAssertFalse(volumes.isEmpty)

        let io = monitor.sampleIO()
        XCTAssertGreaterThanOrEqual(io.readBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(io.writeBytesPerSec, 0)
        Thread.sleep(forTimeInterval: 0.08)
        let secondIO = monitor.sampleIO()
        XCTAssertGreaterThanOrEqual(secondIO.readBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(secondIO.writeBytesPerSec, 0)
        XCTAssertFalse(monitor.sampleVolumes().isEmpty)
    }

    func testNetworkMonitorSampling() {
        let monitor = NetworkMonitor()
        let net = monitor.sample()
        XCTAssertGreaterThanOrEqual(net.uploadBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(net.downloadBytesPerSec, 0)
        Thread.sleep(forTimeInterval: 0.08)
        let second = monitor.sample()
        XCTAssertGreaterThanOrEqual(second.uploadBytesPerSec, 0)
        XCTAssertGreaterThanOrEqual(second.downloadBytesPerSec, 0)
    }

    func testBatteryThermalMonitor() {
        let monitor = BatteryThermalMonitor()
        let snapshot = monitor.sample()
        XCTAssertNotNil(snapshot.thermalState)
    }

    func testEveryThermalSensorTargetHasCompletePresentationMetadata() {
        XCTAssertEqual(ThermalSensorTarget.allCases.count, 9)
        for target in ThermalSensorTarget.allCases {
            XCTAssertEqual(target.id, target.rawValue)
            XCTAssertFalse(target.displayName.isEmpty)
            XCTAssertFalse(target.shortName.isEmpty)
            XCTAssertFalse(target.iconName.isEmpty)
            XCTAssertGreaterThan(target.defaultTargetTemp, 0)
            XCTAssertFalse(target.description.isEmpty)
        }
    }

    func testDockerSamplingUsesInjectedReadOnlyCommandsAndCachesResult() {
        let calls = CallCounter()
        let monitor = ProcessMonitor(
            dockerExecutableProvider: { "/fixture/docker" },
            dockerCommandRunner: { path, arguments in
                XCTAssertEqual(path, "/fixture/docker")
                calls.increment()
                if arguments.first == "stats" {
                    return #"{"Container":"abcdef1234567890","ID":"abcdef123456","Name":"api","CPUPerc":"2.5%","MemUsage":"10MiB / 1GiB","MemPerc":"1.0%"}"#
                }
                return #"{"ID":"abcdef1234567890","Names":"api","Image":"fixture:latest","Status":"Up 1 minute","RunningFor":"1 minute","Command":"serve"}"#
            }
        )

        let first = monitor.sampleDockerContainers()
        let cached = monitor.sampleDockerContainers()
        XCTAssertEqual(first.first?.image, "fixture:latest")
        XCTAssertEqual(cached.first?.containerId, "abcdef123456")
        XCTAssertEqual(calls.count, 2)

        let unavailable = ProcessMonitor(
            dockerExecutableProvider: { "/fixture/docker" },
            dockerCommandRunner: { _, _ in nil }
        )
        XCTAssertTrue(unavailable.sampleDockerContainers().isEmpty)
    }

    func testAIProcessContextClassificationCoversProviderSpecificEvidence() throws {
        let antigravity = try XCTUnwrap(ProcessMonitor.resolveAIContext(
            rawName: "worker",
            args: [],
            cmdSummary: "antigravity worker",
            cwdInfo: ("/tmp/.gemini/antigravity/brain/abcdefgh1234/task", "project"),
            triggerInfo: (nil, [])
        ))
        XCTAssertEqual(antigravity.toolName, "Antigravity Agent")
        XCTAssertEqual(antigravity.sessionId, "abcdefgh1234")

        let claude = try XCTUnwrap(ProcessMonitor.resolveAIContext(
            rawName: "claude",
            args: ["claude", "--model", "sonnet", "--session-id", "session-1"],
            cmdSummary: "claude pytest",
            cwdInfo: ("/tmp/project", "project"),
            triggerInfo: (nil, [])
        ))
        XCTAssertEqual(claude.modelName, "sonnet")
        XCTAssertEqual(claude.sessionId, "session-1")
        XCTAssertEqual(claude.taskSummary, "pytest 單元測試")

        XCTAssertEqual(ProcessMonitor.resolveAIContext(
            rawName: "claude",
            args: ["claude", "wf_12345678"],
            cmdSummary: "claude",
            cwdInfo: ("/tmp", "project"),
            triggerInfo: (nil, [])
        )?.sessionId, "wf_12345678")
        XCTAssertEqual(ProcessMonitor.resolveAIContext(
            rawName: "claude",
            args: ["claude"],
            cmdSummary: "claude",
            cwdInfo: ("/tmp", "工作區 fallback-session"),
            triggerInfo: (nil, [])
        )?.sessionId, "fallback-session")

        let codex = try XCTUnwrap(ProcessMonitor.resolveAIContext(
            rawName: "codex",
            args: ["codex", "--session", "codex-session"],
            cmdSummary: "/opt/codex swift build",
            cwdInfo: ("/tmp/project", "project"),
            triggerInfo: (nil, [])
        ))
        XCTAssertEqual(codex.sessionId, "codex-session")
        XCTAssertEqual(codex.taskSummary, "編譯建構 (Build)")

        XCTAssertEqual(ProcessMonitor.resolveAIContext(
            rawName: "ollama",
            args: ["ollama", "run", "qwen3"],
            cmdSummary: "ollama run qwen3",
            cwdInfo: (nil, nil),
            triggerInfo: (nil, [])
        )?.modelName, "qwen3")
        XCTAssertEqual(ProcessMonitor.resolveAIContext(
            rawName: "llama-server",
            args: ["llama-server", "--model", "/models/local.gguf"],
            cmdSummary: "llama-server --model /models/local.gguf",
            cwdInfo: (nil, nil),
            triggerInfo: (nil, [])
        )?.modelName, "local.gguf")

        let cursor = try XCTUnwrap(ProcessMonitor.resolveAIContext(
            rawName: "worker",
            args: ["worker", "--model", "cursor-model"],
            cmdSummary: "cursor npm run test",
            cwdInfo: ("/tmp/project", "project"),
            triggerInfo: (nil, [])
        ))
        XCTAssertEqual(cursor.toolName, "Cursor AI")
        XCTAssertEqual(cursor.modelName, "cursor-model")
        XCTAssertEqual(cursor.taskSummary, "Node 套件執行")

        for (trigger, expectedTool) in [
            ("Claude Code", "Claude Code"),
            ("Antigravity", "Antigravity Agent"),
            ("Cursor", "Cursor AI")
        ] {
            let context = try XCTUnwrap(ProcessMonitor.resolveAIContext(
                rawName: "worker",
                args: [],
                cmdSummary: "worker",
                cwdInfo: ("/tmp", "工作區 linked-session"),
                triggerInfo: (trigger, [])
            ))
            XCTAssertEqual(context.toolName, expectedTool)
            XCTAssertEqual(context.sessionId, "linked-session")
        }

        XCTAssertNil(ProcessMonitor.resolveAIContext(
            rawName: "worker",
            args: [],
            cmdSummary: "ordinary worker",
            cwdInfo: (nil, nil),
            triggerInfo: (nil, [])
        ))
    }
}
