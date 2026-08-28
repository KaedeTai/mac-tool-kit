import Foundation
import SwiftUI
import Combine
import MacToolKitCore

public enum DashboardTab: String, CaseIterable, Identifiable {
    case overview = "系統總覽"
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
        case .lagDetective: return "2"
        case .cpu: return "3"
        case .memory: return "4"
        case .diskNetwork: return "5"
        case .thermalFan: return "6"
        case .processes: return "7"
        }
    }
}

@MainActor
public final class DashboardViewModel: ObservableObject {
    public static let shared = DashboardViewModel()

    // Navigation state
    @Published public var selectedTab: DashboardTab = .overview

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
        monitorTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                await self.performSample()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    public func performSample() async {
        // Collect all metrics in a single background thread to minimize context switches
        let cpuMon = cpuMonitor
        let memMon = memoryMonitor
        let procMon = processMonitor
        let diskMon = diskMonitor
        let netMon = networkMonitor
        let btMon = batteryThermalMonitor
        let smc = smcBridge

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
                let cpu = cpuMon.sample()
                let mem = memMon.sample()
                let procs = procMon.sampleProcesses(limit: 60)
                let vols = diskMon.sampleVolumes()
                let dIO = diskMon.sampleIO()
                let nIO = netMon.sample()
                let bt = btMon.sample()
                let fans = smc.getFanStatuses()
                let dockers = procMon.sampleDockerContainers()
                return (cpu, mem, procs, vols, dIO, nIO, bt, fans, dockers)
            }
        }.value

        // Atomic batch update on MainActor
        self.cpuSnapshot = sample.cpu
        self.memorySnapshot = sample.mem
        self.processes = sample.procs
        self.diskVolumes = sample.vols
        self.diskIOSnapshot = sample.dIO
        self.networkIOSnapshot = sample.nIO
        self.batteryThermalSnapshot = sample.bt
        self.fanStatuses = sample.fans
        self.dockerContainers = sample.dockers

        self.appendHistory(value: sample.cpu.totalUsage, to: &self.cpuHistory)
        self.appendHistory(value: sample.mem.usedPercentage, to: &self.memoryHistory)
        self.appendHistory(value: sample.nIO.downloadBytesPerSec / (1024 * 1024), to: &self.networkDownHistory)
        self.appendHistory(value: sample.nIO.uploadBytesPerSec / (1024 * 1024), to: &self.networkUpHistory)
    }

    public func refreshAll() {
        Task { @MainActor in
            await performSample()
        }
    }

    private func appendHistory(value: Double, to history: inout [Double]) {
        history.append(value)
        if history.count > 30 {
            history.removeFirst()
        }
    }

    public var filteredProcesses: [ProcessItem] {
        var list = processes
        if onlyUserApps {
            list = list.filter { $0.isUserApp }
        }
        if !processSearchText.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = processSearchText.lowercased()
            list = list.filter {
                $0.name.lowercased().contains(query) ||
                $0.rawName.lowercased().contains(query) ||
                String($0.pid).contains(query) ||
                ($0.projectName?.lowercased().contains(query) ?? false) ||
                ($0.triggerAppName?.lowercased().contains(query) ?? false) ||
                ($0.commandLine?.lowercased().contains(query) ?? false) ||
                ($0.bundleIdentifier?.lowercased().contains(query) ?? false)
            }
        }
        if processSortByCPU {
            list.sort { $0.cpuPercentage > $1.cpuPercentage }
        } else {
            list.sort { $0.memoryBytes > $1.memoryBytes }
        }
        return list
    }

    public func terminateProcess(pid: pid_t, force: Bool = true) {
        let success = processMonitor.terminateProcess(pid: pid, force: force)
        if success {
            showStatus("已成功結束行程 (PID \(pid))")
            refreshAll()
        } else {
            showStatus("無法結束行程 (PID \(pid))，可能需要更高權限")
        }
    }

    public func lowerProcessPriority(pid: pid_t) {
        let success = processMonitor.lowerPriority(pid: pid)
        if success {
            showStatus("已將 PID \(pid) 優先權降至最低")
        } else {
            showStatus("降低優先權失敗")
        }
    }

    public func purgeMemory() {
        let success = smcBridge.purgeMemory()
        if success {
            showStatus("已完成系統快取記憶體釋放！")
        } else {
            showStatus("快取記憶體釋放指令已送出")
        }
        refreshAll()
    }

    public func showStatus(_ msg: String) {
        self.statusMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            if self?.statusMessage == msg {
                self?.statusMessage = nil
            }
        }
    }
}
