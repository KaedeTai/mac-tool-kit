import Foundation
import SwiftUI
import Combine
import MacToolKitCore

@MainActor
public final class LagDetectiveViewModel: ObservableObject {
    public static let shared = LagDetectiveViewModel()

    @Published public var report = LagDiagnosticReport()
    @Published public var isAnalyzing = false
    @Published public var lastDiagnosisTime: Date?
    @Published public var actionFeedbackMessage: String?

    private let detective = LagDetective()

    public init() {}

    public func runDiagnosis(from dashboardVM: DashboardViewModel) {
        isAnalyzing = true
        let cpu = dashboardVM.cpuSnapshot
        let mem = dashboardVM.memorySnapshot
        let procs = dashboardVM.processes
        let bt = dashboardVM.batteryThermalSnapshot
        let dIO = dashboardVM.diskIOSnapshot

        Task.detached(priority: .userInitiated) { [detective] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            let newReport = detective.diagnose(
                cpu: cpu,
                memory: mem,
                processes: procs,
                batteryThermal: bt,
                diskIO: dIO
            )

            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.report = newReport
                self.lastDiagnosisTime = Date()
                self.isAnalyzing = false
            }
        }
    }

    public func executeAction(_ action: RemediationAction, dashboardVM: DashboardViewModel) {
        switch action.typeId {
        case "kill_cpu_hog", "kill_mem_hog":
            if let pid = action.pid {
                dashboardVM.terminateProcess(pid: pid, force: true)
                showFeedback("已執行：強制結束行程 (PID \(pid))")
            }
        case "renice_cpu_hog":
            if let pid = action.pid {
                dashboardVM.lowerProcessPriority(pid: pid)
                showFeedback("已執行：降低行程優先權 (PID \(pid))")
            }
        case "purge_memory":
            dashboardVM.purgeMemory()
            showFeedback("已執行：釋放系統記憶體快取")
        case "fan_max_cooling":
            SMCBridge.shared.setFanMode(.maxCooling)
            showFeedback("已啟動：強效冷卻全速散熱模式！")
            dashboardVM.refreshAll()
        default:
            break
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.runDiagnosis(from: dashboardVM)
        }
    }

    private func showFeedback(_ msg: String) {
        self.actionFeedbackMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            if self?.actionFeedbackMessage == msg {
                self?.actionFeedbackMessage = nil
            }
        }
    }
}
