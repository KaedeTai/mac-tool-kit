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
                showFeedback("已送出結束行程請求 (PID \(pid))；結果以重新取樣為準")
            }
        case "renice_cpu_hog":
            if let pid = action.pid {
                dashboardVM.lowerProcessPriority(pid: pid)
                showFeedback("已送出降低優先權請求 (PID \(pid))；結果見狀態訊息")
            }
        case "open_memory_inspector":
            dashboardVM.selectedTab = .memory
            showFeedback("已打開記憶體排行；inactive pages 由 macOS 自動回收")
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
