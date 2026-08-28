import SwiftUI
import AppKit
import MacToolKitCore

@main
struct MacDashboardApp: App {
    @StateObject private var dashboardVM = DashboardViewModel.shared
    @StateObject private var lagVM = LagDetectiveViewModel.shared
    @StateObject private var fanVM = FanControlViewModel.shared

    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Main Dashboard Window
        Window("Mac 運作監控臺 (Dashboard)", id: "main_dashboard") {
            MainWindowView(
                dashboardVM: dashboardVM,
                lagVM: lagVM,
                fanVM: fanVM
            )
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 680)

        // Menu Bar Extra Status Item
        MenuBarExtra("Mac Dashboard", systemImage: "gauge.with.dots.needle.bottom.50percent") {
            Button("打開完整監控主視窗...") {
                openWindow(id: "main_dashboard")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut("o")

            Divider()

            Text("CPU 總負載: \(String(format: "%.1f%%", dashboardVM.cpuSnapshot.totalUsage))")
            Text("RAM 佔用: \(String(format: "%.1f%%", dashboardVM.memorySnapshot.usedPercentage))")
            Text("風扇轉速: \(dashboardVM.fanStatuses.first?.currentRPM ?? 1800) RPM")

            Divider()

            Button("一鍵釋放記憶體快取 (Purge)") {
                dashboardVM.purgeMemory()
            }

            Button("全速冷卻散熱 (Max Turbo)") {
                fanVM.selectMode(.maxCooling)
            }

            Divider()

            Button("結束 Mac Dashboard") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
