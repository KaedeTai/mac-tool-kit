import SwiftUI
import MacToolKitCore

public struct MainWindowView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var lagVM: LagDetectiveViewModel
    @ObservedObject var fanVM: FanControlViewModel
    @ObservedObject var aiVM: AIAnalyticsViewModel

    @MainActor
    public init(
        dashboardVM: DashboardViewModel,
        lagVM: LagDetectiveViewModel,
        fanVM: FanControlViewModel,
        aiVM: AIAnalyticsViewModel
    ) {
        self.dashboardVM = dashboardVM
        self.lagVM = lagVM
        self.fanVM = fanVM
        self.aiVM = aiVM
    }

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar Navigation
            VStack(alignment: .leading, spacing: 0) {
                // Header Branding
                HStack(spacing: 10) {
                    Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac Tool Kit")
                            .font(.system(size: 15, weight: .bold))
                        Text("Dashboard & 排障")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 16)

                Divider()

                // Navigation Tab Buttons
                VStack(spacing: 4) {
                    ForEach(DashboardTab.allCases) { tab in
                        let isSelected = dashboardVM.selectedTab == tab
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                dashboardVM.selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: tab.iconName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .frame(width: 24)
                                    .foregroundColor(isSelected ? .white : .accentColor)

                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .primary)

                                Spacer()

                                if tab == .lagDetective && lagVM.report.severity != .smooth {
                                    Circle()
                                        .fill(Color.orange)
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(tab.keyboardShortcutKey, modifiers: .command)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)

                Spacer()

                Divider()

                // Sidebar Footer (Status & Manual Refresh)
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    Text("即時監控中")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        Task {
                            await dashboardVM.performSample()
                            lagVM.runDiagnosis(from: dashboardVM)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("立即手動重新整理數據")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(width: 210)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))

            Divider()

            // MARK: - Right Detail Content
            VStack(spacing: 0) {
                // Context title and global monitoring controls. Navigation lives
                // in the sidebar, so it is intentionally not duplicated here.
                HStack {
                    Text(dashboardVM.selectedTab.rawValue)
                        .font(.title2.bold())

                    Spacer()

                    // Monitoring Profile Switcher (Eco / Real-time)
                    Menu {
                        ForEach(MonitoringProfile.allCases) { profile in
                            Button {
                                dashboardVM.monitoringProfile = profile
                            } label: {
                                HStack {
                                    Image(systemName: profile.iconName)
                                    Text(profile.title)
                                    if dashboardVM.monitoringProfile == profile {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: dashboardVM.monitoringProfile.iconName)
                                .foregroundColor(dashboardVM.monitoringProfile == .fanOnlyEco ? .green : .accentColor)
                            Text(dashboardVM.monitoringProfile.shortTitle)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                    }
                    .menuStyle(.borderlessButton)
                    .help("監控模式切換：\(dashboardVM.monitoringProfile.description)")

                    Button {
                        Task {
                            await dashboardVM.performSample()
                            lagVM.runDiagnosis(from: dashboardVM)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .padding(6)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help("重新整理")
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                Divider()

                // Main Tab Content View
                Group {
                    switch dashboardVM.selectedTab {
                    case .overview:
                        OverviewView(dashboardVM: dashboardVM, lagVM: lagVM)
                    case .aiAnalytics:
                        AIAnalyticsView(viewModel: aiVM)
                    case .lagDetective:
                        LagDetectiveView(dashboardVM: dashboardVM, lagVM: lagVM)
                    case .cpu:
                        CPUView(dashboardVM: dashboardVM)
                    case .memory:
                        MemoryView(dashboardVM: dashboardVM)
                    case .diskNetwork:
                        DiskNetworkView(dashboardVM: dashboardVM)
                    case .thermalFan:
                        ThermalFanView(dashboardVM: dashboardVM, fanVM: fanVM)
                    case .processes:
                        ProcessTableView(dashboardVM: dashboardVM)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 1000, minHeight: 680)
        .onAppear {
            Task {
                await dashboardVM.performSample()
            }
        }
    }
}
