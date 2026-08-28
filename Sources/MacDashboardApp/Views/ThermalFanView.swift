import SwiftUI
import MacToolKitCore

public struct ThermalFanView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var fanVM: FanControlViewModel

    private let presetModes: [FanMode] = [
        .automatic,
        .quiet(targetTemp: 75),
        .balanced(targetTemp: 65),
        .maxCooling
    ]

    private func getModeTitle(_ mode: FanMode, target: ThermalSensorTarget) -> String {
        switch mode {
        case .automatic:
            return "原廠動態 (Auto)"
        case .quiet:
            let temp = target == .palmRest ? 36 : (target == .socPackage ? 70 : 75)
            return "靜音策略 (目標 ≤ \(temp)°C)"
        case .balanced:
            let temp = target == .palmRest ? 34 : (target == .socPackage ? 60 : 65)
            return "智慧溫控 (目標 ≤ \(temp)°C)"
        case .maxCooling:
            let temp = target == .palmRest ? 32 : (target == .socPackage ? 48 : 50)
            return "極限壓溫 (目標 ≤ \(temp)°C)"
        case .custom(let rpm):
            return "自訂固定轉速 (\(rpm) RPM)"
        }
    }

    private func getModeDescription(_ mode: FanMode, target: ThermalSensorTarget) -> String {
        switch mode {
        case .automatic:
            return "由 macOS 系統微碼自動控溫，低負載時靜音，高溫時升速"
        case .quiet:
            let temp = target == .palmRest ? 36 : (target == .socPackage ? 70 : 75)
            return "\(target.shortName)未達 \(temp)°C 前維持最低轉速，享受極致安靜"
        case .balanced:
            let temp = target == .palmRest ? 34 : (target == .socPackage ? 60 : 65)
            return "維持\(target.shortName)在 \(temp)°C 內，中等負載提早排熱防止積熱"
        case .maxCooling:
            let temp = target == .palmRest ? 32 : (target == .socPackage ? 48 : 50)
            return "全速運轉強力壓制\(target.shortName)在 \(temp)°C 內，快速降溫"
        case .custom:
            return "手動強制鎖定固定轉速"
        }
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Success / Info Message alert
                if let msg = fanVM.message {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                }

                // Error Message alert
                if let err = fanVM.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.12))
                    .cornerRadius(10)
                }

                // Monitoring Profile & Eco Mode Banner
                HStack {
                    Image(systemName: dashboardVM.monitoringProfile == .fanOnlyEco ? "leaf.fill" : "bolt.fill")
                        .foregroundColor(dashboardVM.monitoringProfile == .fanOnlyEco ? .green : .blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("背景監控效能模式：\(dashboardVM.monitoringProfile.title)")
                            .font(.system(size: 12, weight: .bold))
                        Text(dashboardVM.monitoringProfile.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $dashboardVM.monitoringProfile) {
                        ForEach(MonitoringProfile.allCases) { p in
                            Text(p.shortTitle).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .cornerRadius(8)

                // Helper Activation Card
                if !fanVM.isHelperRunning {
                    GlassCard(title: "硬體風扇特權控制 (Hardware Fan Control)", iconName: "lock.shield.fill", accentColor: .blue) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 26))
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("一鍵啟用硬體層級物理風扇接管")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("支援如同 Macs Fan Control 的 XPC SMC 協議。啟用後可自訂掌托、CPU、GPU 等不同元件的目標控溫與手動固定調速。")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }

                            Divider()

                            HStack {
                                Text("🔒 支援隨時一鍵完整卸載還原原廠自動")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button {
                                    fanVM.installHelperAction()
                                } label: {
                                    HStack(spacing: 6) {
                                        if fanVM.isInstallingHelper {
                                            ProgressView()
                                                .controlSize(.small)
                                        } else {
                                            Image(systemName: "arrow.down.circle.fill")
                                        }
                                        Text(fanVM.isInstallingHelper ? "授權安裝中..." : "啟用硬體風扇控制 (需授權)")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .disabled(fanVM.isInstallingHelper)
                            }
                        }
                    }
                } else {
                    // Helper Active Status Bar
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 16))
                        Text("特權硬體助手已連線 (SMC Root Controller Active)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)

                        Spacer()

                        Button("解除特權助手") {
                            fanVM.uninstallHelperAction()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .disabled(fanVM.isInstallingHelper)
                    }
                    .padding(10)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                }

                // 1. All Hardware Components Real-time Temperature Grid
                GlassCard(title: "全機各硬體元件即時溫度 (Component Temperatures)", iconName: "thermometer.sun.fill", accentColor: .orange) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("點擊下方任一元件卡片，即可切換為該元件的「專屬溫控基準」：")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(fanVM.componentReadings) { reading in
                                Button {
                                    fanVM.selectSensorTarget(reading.target)
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: reading.iconName)
                                                .font(.system(size: 14))
                                                .foregroundColor(reading.isHotspot ? .red : (fanVM.selectedSensorTarget == reading.target ? .accentColor : .primary))

                                            Text(reading.name)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(fanVM.selectedSensorTarget == reading.target ? .accentColor : .primary)
                                                .lineLimit(1)

                                            Spacer()

                                            if fanVM.selectedSensorTarget == reading.target {
                                                Text("當前基準")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.accentColor.opacity(0.2))
                                                    .foregroundColor(.accentColor)
                                                    .cornerRadius(4)
                                            } else if reading.isHotspot {
                                                Text("最高溫")
                                                    .font(.system(size: 9, weight: .bold))
                                                    .padding(.horizontal, 5)
                                                    .padding(.vertical, 2)
                                                    .background(Color.red.opacity(0.2))
                                                    .foregroundColor(.red)
                                                    .cornerRadius(4)
                                            }
                                        }

                                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                                            Text(String(format: "%.1f", reading.temperatureCelsius))
                                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                                .foregroundColor(reading.temperatureCelsius > 65 ? .orange : (reading.temperatureCelsius > 80 ? .red : .primary))
                                            Text("°C")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.secondary)
                                        }

                                        Text(reading.locationDescription)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(fanVM.selectedSensorTarget == reading.target ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(fanVM.selectedSensorTarget == reading.target ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // 2. Real-time Fan Speed Tachometers
                GlassCard(title: "即時物理風扇轉速 (Real-Time Fan Speed)", iconName: "fan.fill", accentColor: .blue) {
                    VStack(spacing: 14) {
                        HStack(spacing: 24) {
                            if fanVM.fanStatuses.isEmpty {
                                Text("未檢測到風扇或正在讀取硬體傳感器...")
                                    .font(.system(size: 13))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(16)
                            } else {
                                ForEach(fanVM.fanStatuses) { fan in
                                    VStack(spacing: 8) {
                                        Image(systemName: "fanblades.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(fan.currentRPM > 0 ? .blue : .secondary)

                                        Text(fan.name)
                                            .font(.system(size: 13, weight: .medium))

                                        Text("\(fan.currentRPM) RPM")
                                            .font(.system(size: 20, weight: .bold, design: .rounded))
                                            .foregroundColor(fan.currentRPM > 4500 ? .orange : (fan.currentRPM > 0 ? .primary : .secondary))

                                        if fan.currentRPM == 0 {
                                            Text("低溫靜音停轉中 (0 RPM)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.green)
                                        } else {
                                            Text("即時轉速生效中 (目標 \(fan.targetRPM) RPM)")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(.blue)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(16)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                    .cornerRadius(12)
                                }
                            }
                        }

                        // Closed-loop Dynamic Status Indicator
                        HStack(spacing: 8) {
                            Image(systemName: "thermometer.snowflake")
                                .foregroundColor(.accentColor)
                                .font(.system(size: 13))
                            Text("動態溫控響應：\(fanVM.fanStateDescription)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }

                // 3. Sensor Target Selector & Preset Modes
                GlassCard(title: "風扇散熱策略與基準元件 (Fan Control Target & Profiles)", iconName: "slider.horizontal.3", accentColor: .indigo) {
                    VStack(alignment: .leading, spacing: 16) {
                        // Current Sensor Target Header
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("目前散熱基準元件：\(fanVM.selectedSensorTarget.displayName)")
                                    .font(.system(size: 13, weight: .bold))
                                Text(fanVM.selectedSensorTarget.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu {
                                ForEach(ThermalSensorTarget.allCases) { target in
                                    Button {
                                        fanVM.selectSensorTarget(target)
                                    } label: {
                                        HStack {
                                            Image(systemName: target.iconName)
                                            Text(target.displayName)
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                    Text("更換基準元件")
                                }
                                .font(.system(size: 11))
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)

                        Divider()

                        Text("選擇目標溫控策略，風扇會根據【\(fanVM.selectedSensorTarget.shortName)】即時溫度自動動態調節：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        // Preset Buttons
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(presetModes, id: \.title) { mode in
                                Button {
                                    fanVM.selectMode(mode)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: mode.iconName)
                                            .font(.system(size: 18))
                                            .frame(width: 24)

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(getModeTitle(mode, target: fanVM.selectedSensorTarget))
                                                    .font(.system(size: 13, weight: .bold))
                                                Spacer()
                                                if let target = mode.targetTemperatureCelsius {
                                                    let displayTarget = fanVM.selectedSensorTarget == .palmRest ? (target == 50 ? 32 : (target == 65 ? 34 : 36)) : (fanVM.selectedSensorTarget == .socPackage ? (target == 50 ? 48 : (target == 65 ? 60 : 70)) : target)
                                                    Text("目標 ≤ \(displayTarget)°C")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(Color.blue.opacity(0.15))
                                                        .foregroundColor(.blue)
                                                        .cornerRadius(4)
                                                }
                                            }

                                            Text(getModeDescription(mode, target: fanVM.selectedSensorTarget))
                                                .font(.system(size: 11))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
                                        }
                                        Spacer()
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(fanVM.selectedMode == mode ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(fanVM.selectedMode == mode ? Color.accentColor : Color.clear, lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Divider()

                        // Manual RPM Slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("手動自訂固定轉速 (強制鎖定覆寫):")
                                    .font(.system(size: 13, weight: .bold))
                                Spacer()
                                Text("\(Int(fanVM.customRPM)) RPM")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(.accentColor)
                            }

                            Slider(value: $fanVM.customRPM, in: 1200...6200, step: 100)
                                .tint(.accentColor)

                            HStack {
                                Text("1200 RPM (極靜低轉)").font(.caption).foregroundColor(.secondary)
                                Spacer()
                                Button("套用自訂轉速") {
                                    fanVM.applyCustomRPM()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                Spacer()
                                Text("6200 RPM (極限全速)").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(10)
                    }
                }

                // 4. Power & Battery Status
                GlassCard(title: "電池與電源供應狀態 (Power & Battery)", iconName: "battery.100.bolt", accentColor: .teal) {
                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("SoC 晶片熱壓等級:").foregroundColor(.secondary)
                                Spacer()
                                StatBadge(
                                    text: dashboardVM.batteryThermalSnapshot.thermalState.rawValue,
                                    iconName: dashboardVM.batteryThermalSnapshot.thermalState == .nominal ? "checkmark.circle.fill" : "flame.fill",
                                    color: dashboardVM.batteryThermalSnapshot.thermalState == .nominal ? .green : .orange
                                )
                            }

                            if dashboardVM.batteryThermalSnapshot.hasBattery {
                                HStack {
                                    Text("掌托內部電池溫度:").foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.1f °C", dashboardVM.batteryThermalSnapshot.batteryTemperatureCelsius)) (正常安全區間)").bold()
                                }

                                HStack {
                                    Text("即時供電功耗 (Power):").foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2f W", dashboardVM.batteryThermalSnapshot.powerWattage)).bold()
                                }

                                HStack {
                                    Text("電池健康度與循環:").foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(String(format: "%.0f", dashboardVM.batteryThermalSnapshot.healthPercentage))% (循環 \(dashboardVM.batteryThermalSnapshot.cycleCount) 次)").bold()
                                }
                            }
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .padding(20)
        }
    }
}
