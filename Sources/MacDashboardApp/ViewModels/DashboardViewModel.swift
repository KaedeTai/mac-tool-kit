import Foundation
import SwiftUI
import Combine
import MacToolKitCore

public enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "系統總覽"
    case aiAnalytics = "AI 寫程式分析"
    case lagDetective = "Lag 診斷中心"
    case cpu = "CPU 運算"
    case memory = "記憶體 RAM"
    case diskNetwork = "磁碟與網路"
    case thermalFan = "風扇與散熱"
    case processes = "行程管理員"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.bottom.50percent"
        case .aiAnalytics: return "brain.head.profile"
        case .lagDetective: return "stethoscope"
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .diskNetwork: return "network"
        case .thermalFan: return "fanblades.fill"
        case .processes: return "list.bullet.rectangle.portrait"
        }
    }

    public var keyboardShortcutKey: KeyEquivalent {
        switch self {
        case .overview: return "1"
        case .aiAnalytics: return "2"
        case .lagDetective: return "3"
        case .cpu: return "4"
        case .memory: return "5"
        case .diskNetwork: return "6"
        case .thermalFan: return "7"
        case .processes: return "8"
        }
    }
}

public enum MonitoringProfile: String, CaseIterable, Identifiable, Sendable {
    case realtime = "realtime"      // 1s Full Spectrum (~2-4% CPU)
    case balanced = "balanced"      // 3s Low Overhead (~0.5-1% CPU)
    case fanOnlyEco = "fanOnlyEco"  // Fan-Only Eco Mode (< 0.1% CPU)

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .realtime: return "即時全景 (1秒)"
        case .balanced: return "平衡節能 (3秒)"
        case .fanOnlyEco: return "僅風扇控溫 (極致省電)"
        }
    }

    public var shortTitle: String {
        switch self {
        case .realtime: return "即時 (1s)"
        case .balanced: return "平衡 (3s)"
        case .fanOnlyEco: return "僅風扇 (Eco)"
        }
    }

    public var iconName: String {
        switch self {
        case .realtime: return "bolt.fill"
        case .balanced: return "leaf.fill"
        case .fanOnlyEco: return "fanblades.fill"
        }
    }

    public var description: String {
        switch self {
        case .realtime: return "每秒刷新所有硬體、行程與 Docker 數據（約佔 2~4% CPU）"
        case .balanced: return "每 3 秒刷新一次，降低系統開銷（約佔 0.5~1% CPU）"
        case .fanOnlyEco: return "暫停行程與 Docker 掃描，僅維持風扇動態溫控（極致省電 < 0.1% CPU）"
        }
    }
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    public static let shared = DashboardViewModel()

    // Navigation state
    @Published public var selectedTab: DashboardTab = .overview

    // Monitoring Mode Profile
    @Published public var monitoringProfile: MonitoringProfile = .realtime {
        didSet {
            startMonitoring()
        }
    }

    // Current Live Metrics
    @Published public var cpuSnapshot = CPUUsageSnapshot()
    @Published public var memorySnapshot = MemoryUsageSnapshot()
    @Published public var processes: [ProcessItem] = []
    @Published public var diskVolumes: [DiskVolumeInfo] = []
    @Published public var diskIOSnapshot = DiskIOSnapshot()
    @Published public var networkIOSnapshot = NetworkIOSnapshot()
    @Published public var batteryThermalSnapshot = BatteryThermalSnapshot()
    @Published public var fanStatuses: [FanStatus] = []
    @Published public var dockerContainers: [DockerContainerInfo] = []

    // History for Sparkline Graphs (Last 30 points)
    @Published public var cpuHistory: [Double] = Array(repeating: 0, count: 30)
    @Published public var memoryHistory: [Double] = Array(repeating: 0, count: 30)
    @Published public var networkDownHistory: [Double] = Array(repeating: 0, count: 30)
    @Published public var networkUpHistory: [Double] = Array(repeating: 0, count: 30)

    // Filtering & UI State
    @Published public var processSearchText: String = ""
    @Published public var onlyUserApps: Bool = false
    @Published public var processSortByCPU: Bool = true
    @Published public var statusMessage: String? = nil

    // Services
    private let cpuMonitor = CPUMonitor()
    private let memoryMonitor = MemoryMonitor()
    private let processMonitor = ProcessMonitor()
    private let diskMonitor = DiskMonitor()
    private let networkMonitor = NetworkMonitor()
    private let batteryThermalMonitor = BatteryThermalMonitor()
    private let smcBridge = SMCBridge.shared

    private var monitorTask: Task<Void, Never>?

    public init() {
        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
    }

    public func startMonitoring() {
        monitorTask?.cancel()
        let intervalSec: Double
        switch monitoringProfile {
        case .realtime: intervalSec = 1.0
        case .balanced: intervalSec = 3.0
        case .fanOnlyEco: intervalSec = 3.0
        }

        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.performSample()
                try? await Task.sleep(nanoseconds: UInt64(intervalSec * 1_000_000_000))
            }
        }
    }

    public func performSample() async {
        let cpuMon = cpuMonitor
        let memMon = memoryMonitor
        let procMon = processMonitor
        let diskMon = diskMonitor
        let netMon = networkMonitor
        let btMon = batteryThermalMonitor
        let smc = smcBridge
        let isFanOnly = monitoringProfile == .fanOnlyEco

        let sample = await Task.detached(priority: .userInitiated) {
            autoreleasepool { () -> (
                cpu: CPUUsageSnapshot,
                mem: MemoryUsageSnapshot,
                procs: [ProcessItem],
                vols: [DiskVolumeInfo],
                dIO: DiskIOSnapshot,
                nIO: NetworkIOSnapshot,
                bt: BatteryThermalSnapshot,
                fans: [FanStatus],
                dockers: [DockerContainerInfo]
            ) in
                let bt = btMon.sample()
                let fans = smc.getFanStatuses()

                if isFanOnly {
                    // Eco Mode: zero process scanning, zero docker stats, minimal overhead
                    return (CPUUsageSnapshot(), MemoryUsageSnapshot(), [], [], DiskIOSnapshot(), NetworkIOSnapshot(), bt, fans, [])
                }

                let cpu = cpuMon.sample()
                let mem = memMon.sample()
                let procs = procMon.sampleProcesses(limit: 60)
                let vols = diskMon.sampleVolumes()
                let dIO = diskMon.sampleIO()
                let nIO = netMon.sample()
                let dockers = procMon.sampleDockerContainers()
                return (cpu, mem, procs, vols, dIO, nIO, bt, fans, dockers)
            }
        }.value

        // Atomic batch update on MainActor
        self.batteryThermalSnapshot = sample.bt
        self.fanStatuses = sample.fans

        if !isFanOnly {
            self.cpuSnapshot = sample.cpu
            self.memorySnapshot = sample.mem
            self.processes = sample.procs
            self.diskVolumes = sample.vols
            self.diskIOSnapshot = sample.dIO
            self.networkIOSnapshot = sample.nIO
            self.dockerContainers = sample.dockers

            self.appendHistory(value: sample.cpu.totalUsage, to: &self.cpuHistory)
            self.appendHistory(value: sample.mem.usedPercentage, to: &self.memoryHistory)
            self.appendHistory(value: sample.nIO.downloadBytesPerSec / (1024 * 1024), to: &self.networkDownHistory)
            self.appendHistory(value: sample.nIO.uploadBytesPerSec / (1024 * 1024), to: &self.networkUpHistory)
        }
    }

    public func refreshAll() {
        Task { @MainActor in
            await performSample()
        }
    }

    private func appendHistory(value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 30 {
            history.removeFirst(history.count - 30)
        }
    }

    public func terminateProcess(pid: pid_t, force: Bool = true) {
        let success = processMonitor.terminateProcess(pid: pid, force: force)
        if success {
            self.statusMessage = "已成功結束行程 (PID \(pid))"
            refreshAll()
        } else {
            self.statusMessage = "無法結束行程 (PID \(pid))，可能權限不足"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.statusMessage = nil
        }
    }

    public var filteredProcesses: [ProcessItem] {
        var list = processes
        if onlyUserApps {
            list = list.filter { $0.isUserApp }
        }
        if !processSearchText.isEmpty {
            let q = processSearchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(q) ||
                $0.rawName.lowercased().contains(q) ||
                String($0.pid).contains(q) ||
                ($0.bundleIdentifier?.lowercased().contains(q) ?? false)
            }
        }
        if processSortByCPU {
            return list.sorted { $0.cpuPercentage > $1.cpuPercentage }
        } else {
            return list.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    public func purgeMemory() {
        Task {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/purge")
            try? proc.run()
            proc.waitUntilExit()
            await performSample()
            await MainActor.run {
                self.statusMessage = "✅ 已成功釋放系統快取記憶體 (Purge Cache)"
            }
        }
    }

    public func lowerPriority(pid: pid_t) {
        lowerProcessPriority(pid: pid)
    }

    public func lowerProcessPriority(pid: pid_t) {
        let success = processMonitor.lowerPriority(pid: pid)
        if success {
            self.statusMessage = "已成功降低行程優先權 (PID \(pid))"
            refreshAll()
        } else {
            self.statusMessage = "無法更改優先權 (PID \(pid))"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.statusMessage = nil
        }
    }
}
