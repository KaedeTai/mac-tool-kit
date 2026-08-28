import SwiftUI
import MacToolKitCore

public struct ProcessTableView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @State private var processToTerminate: ProcessItem? = nil
    @State private var selectedProcessForDetails: ProcessItem? = nil

    public var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            HStack(spacing: 16) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("搜尋應用程式名稱、PID、專案或指令...", text: $dashboardVM.processSearchText)
                        .textFieldStyle(.plain)
                    if !dashboardVM.processSearchText.isEmpty {
                        Button {
                            dashboardVM.processSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                .frame(maxWidth: 320)

                Toggle("僅顯示使用者 App", isOn: $dashboardVM.onlyUserApps)
                    .font(.system(size: 13))

                Spacer()

                // Sort Segmented Control
                Picker("排序依據", selection: $dashboardVM.processSortByCPU) {
                    Text("CPU 佔用").tag(true)
                    Text("RAM 佔用").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))

            Divider()

            // Process Table Header
            HStack(spacing: 12) {
                Text("應用程式 / 行程與專案上下文")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("類別")
                    .frame(width: 90, alignment: .leading)
                Text("PID")
                    .frame(width: 55, alignment: .trailing)
                Text("已運作時間")
                    .frame(width: 90, alignment: .trailing)
                Text("CPU %")
                    .frame(width: 75, alignment: .trailing)
                Text("記憶體佔用 (比例)")
                    .frame(width: 135, alignment: .trailing)
                Text("動作")
                    .frame(width: 70, alignment: .center)
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            // Process List
            List(dashboardVM.filteredProcesses) { proc in
                HStack(spacing: 12) {
                    // App Icon & Name & Project Context
                    HStack(spacing: 10) {
                        Image(systemName: proc.category.iconName)
                            .font(.system(size: 16))
                            .foregroundColor(proc.isUserApp ? .blue : .purple)
                            .frame(width: 22, height: 22)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(proc.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)

                                if let proj = proc.projectName {
                                    Text("📁 \(proj)")
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.blue.opacity(0.15))
                                        .foregroundColor(.blue)
                                        .cornerRadius(4)
                                }

                                if let ai = proc.aiContext {
                                    HStack(spacing: 4) {
                                        Image(systemName: "brain.head.profile")
                                            .font(.system(size: 9))
                                        Text(ai.displayBadge)
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.purple.opacity(0.18))
                                    .foregroundColor(.purple)
                                    .cornerRadius(5)
                                }
                            }

                            HStack(spacing: 6) {
                                if let trigger = proc.triggerAppName {
                                    Text("來自: \(trigger)")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(.secondary)
                                }

                                Text("• \(proc.rawName)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary.opacity(0.8))

                                if let cmd = proc.commandLine, !cmd.isEmpty, cmd != proc.rawName {
                                    Text("• \(cmd)")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedProcessForDetails = proc
                    }

                    // Category
                    Text(proc.category.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .leading)

                    // PID
                    Text("\(proc.pid)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 55, alignment: .trailing)

                    // Uptime
                    Text(proc.formattedUptime)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 90, alignment: .trailing)

                    // CPU %
                    Text(String(format: "%.1f%%", proc.cpuPercentage))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(proc.cpuPercentage > 50 ? .red : (proc.cpuPercentage > 20 ? .orange : .primary))
                        .frame(width: 75, alignment: .trailing)

                    // Memory (with % of total RAM)
                    HStack(spacing: 4) {
                        Text(formatMemory(proc.memoryBytes))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        Text("(\(String(format: "%.1f%%", proc.memoryPercentage)))")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .frame(width: 135, alignment: .trailing)

                    // Actions
                    HStack(spacing: 8) {
                        Button {
                            processToTerminate = proc
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("結束行程：\(proc.terminationImpact)")

                        Button {
                            dashboardVM.lowerProcessPriority(pid: proc.pid)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(.plain)
                        .help("降低優先權 (Renice)")
                    }
                    .frame(width: 70, alignment: .center)
                }
                .padding(.vertical, 4)
                .help("點擊可查看此行程的發起應用、所屬專案目錄與完整指令")
            }
            .listStyle(.plain)
        }
        .confirmationDialog(
            "確定要結束此行程？",
            isPresented: Binding(
                get: { processToTerminate != nil },
                set: { if !$0 { processToTerminate = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let target = processToTerminate {
                Button("強制結束 \(target.name) (PID \(target.pid))", role: .destructive) {
                    dashboardVM.terminateProcess(pid: target.pid)
                    processToTerminate = nil
                }
                Button("取消", role: .cancel) {
                    processToTerminate = nil
                }
            }
        } message: {
            if let target = processToTerminate {
                Text("【\(target.name)】\n\(target.terminationImpact)\n\n• 觸發來源：\(target.triggerAppName ?? "系統")\n• 所屬專案：\(target.projectName ?? "無")\n• 已運作時長：\(target.formattedUptime)\n• CPU 佔用：\(String(format: "%.1f%%", target.cpuPercentage)) | 記憶體：\(formatMemory(target.memoryBytes))")
            }
        }
        .sheet(item: $selectedProcessForDetails) { proc in
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: proc.category.iconName)
                        .font(.system(size: 28))
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(proc.name)
                            .font(.system(size: 16, weight: .bold))
                        Text("PID \(proc.pid) • \(proc.category.rawValue)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        selectedProcessForDetails = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    if let ai = proc.aiContext {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .foregroundColor(.purple)
                                Text("🤖 AI 任務上下文 (AI Agent Context)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.purple)
                            }

                            HStack {
                                Text("• 發起工具:").bold().frame(width: 90, alignment: .leading)
                                Text(ai.toolName)
                            }
                            if let model = ai.modelName {
                                HStack {
                                    Text("• 調用模型:").bold().frame(width: 90, alignment: .leading)
                                    Text(model).font(.system(size: 12, design: .monospaced)).bold()
                                }
                            }
                            if let sId = ai.sessionId {
                                HStack {
                                    Text("• Session ID:").bold().frame(width: 90, alignment: .leading)
                                    Text(sId).font(.system(size: 11, design: .monospaced)).foregroundColor(.secondary)
                                }
                            }
                            if let task = ai.taskSummary {
                                HStack {
                                    Text("• 執行任務:").bold().frame(width: 90, alignment: .leading)
                                    Text(task).foregroundColor(.primary)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(8)
                    }

                    HStack {
                        Text("觸發發起來源:").bold().frame(width: 110, alignment: .leading)
                        Text(proc.triggerAppName ?? "系統核心 / launchd")
                    }

                    if !proc.triggerChain.isEmpty {
                        HStack(alignment: .top) {
                            Text("父進程呼叫鏈:").bold().frame(width: 110, alignment: .leading)
                            Text(proc.triggerChain.joined(separator: " ➔ "))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    if let proj = proc.projectName {
                        HStack {
                            Text("所屬專案名稱:").bold().frame(width: 110, alignment: .leading)
                            Text(proj)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }

                    if let cwd = proc.workingDirectory {
                        HStack(alignment: .top) {
                            Text("工作目錄 (CWD):").bold().frame(width: 110, alignment: .leading)
                            Text(cwd)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    HStack {
                        Text("已運作時長:").bold().frame(width: 110, alignment: .leading)
                        Text("\(proc.formattedUptime)\(proc.startedAt != nil ? " (啟動於 \(proc.startedAt!.formatted(date: .omitted, time: .standard)))" : "")")
                    }

                    HStack {
                        Text("資源使用量:").bold().frame(width: 110, alignment: .leading)
                        Text("\(String(format: "%.1f%% CPU", proc.cpuPercentage)) • \(formatMemory(proc.memoryBytes)) (\(String(format: "%.1f%% RAM", proc.memoryPercentage))) • \(proc.threadCount) 執行緒")
                    }

                    if let cmd = proc.commandLine {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("完整執行指令:").bold()
                            Text(cmd)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("結束影響評估:").bold()
                        Text(proc.terminationImpact)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }
                .font(.system(size: 13))

                Divider()

                HStack {
                    Button("降低優先權 (Renice)") {
                        dashboardVM.lowerProcessPriority(pid: proc.pid)
                    }

                    Spacer()

                    Button("強制結束此行程 (PID \(proc.pid))", role: .destructive) {
                        dashboardVM.terminateProcess(pid: proc.pid)
                        selectedProcessForDetails = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(20)
            .frame(width: 520)
        }
    }

    private func formatMemory(_ bytes: UInt64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.2f GB", mb / 1024)
        } else {
            return String(format: "%.0f MB", mb)
        }
    }
}
