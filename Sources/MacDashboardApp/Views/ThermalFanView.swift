import SwiftUI
import MacToolKitCore

public struct ThermalFanView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var fanVM: FanControlViewModel
    @State private var isMeasuredPointListExpanded = true

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
                if fanVM.fanStatuses.isEmpty {
                    GlassCard(title: "硬體風扇特權控制 (Hardware Fan Control)", iconName: "lock.shield.fill", accentColor: .blue) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "shield.checkered")
                                    .font(.system(size: 26))
                                    .foregroundColor(.blue)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("啟用可驗證的風扇讀寫通道")
                                        .font(.system(size: 14, weight: .bold))
                                    Text("啟用後會先讀回風扇數量、實際 RPM 與硬體範圍。只有完整讀回時才回報成功；CPU、GPU 與統一記憶體溫度也只採 Apple SMC 實測來源。")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                }
                            }

                            if fanVM.isHelperInstalled {
                                Label(
                                    fanVM.helperCapability.localizedDescription,
                                    systemImage: fanVM.helperCapability.hasVerifiedFanReadback
                                        ? "checkmark.shield.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(fanVM.helperCapability.hasVerifiedFanReadback ? .green : .orange)
                            }

                            if let warning = fanVM.helperSecurityWarning {
                                Label(warning, systemImage: "exclamationmark.shield.fill")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.red)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
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
                                        Text(fanVM.isInstallingHelper
                                            ? "授權安裝中..."
                                            : (fanVM.isHelperInstalled ? "重新安裝讀回助手 (需授權)" : "啟用讀回助手 (需授權)"))
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
                        Text("風扇讀寫通道可連線；實際結果以 RPM 讀回為準")
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
                GlassCard(title: "硬體溫度來源可用性 (Measured Sensors)", iconName: "thermometer.sun.fill", accentColor: .orange) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("目前可讀 \(fanVM.measuredComponentReadings.count) 個來源群組、\(fanVM.measuredSensorPointCount) 個具名實測點。上方卡片顯示群組摘要；下方明細保留系統回傳的每個感測點名稱與即時溫度。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }

                        if fanVM.measuredComponentReadings.isEmpty {
                            Label("目前沒有讀到可驗證的實體溫度來源", systemImage: "thermometer.medium.slash")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 24)
                        } else {
                            Text("來源群組摘要（\(fanVM.measuredComponentReadings.count)）")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 10)], spacing: 10) {
                                ForEach(fanVM.measuredComponentReadings) { reading in
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
                                                    .lineLimit(2)

                                                Spacer()

                                                if fanVM.selectedSensorTarget == reading.target {
                                                    Text("當前基準")
                                                        .font(.system(size: 9, weight: .bold))
                                                        .padding(.horizontal, 5)
                                                        .padding(.vertical, 2)
                                                        .background(Color.accentColor.opacity(0.2))
                                                        .foregroundColor(.accentColor)
                                                        .cornerRadius(4)
                                                }
                                            }

                                            if let temperature = reading.temperatureCelsius {
                                                HStack(alignment: .lastTextBaseline, spacing: 4) {
                                                    Text(String(format: "%.1f", temperature))
                                                        .font(.system(size: 22, weight: .bold, design: .rounded))
                                                        .foregroundColor(.primary)
                                                    Text("°C")
                                                        .font(.system(size: 12, weight: .semibold))
                                                        .foregroundColor(.secondary)
                                                }
                                            }

                                            Text(reading.locationDescription)
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                                .lineLimit(2)
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

                            DisclosureGroup(isExpanded: $isMeasuredPointListExpanded) {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(fanVM.measuredComponentReadings) { reading in
                                        if !reading.measuredPoints.isEmpty {
                                            VStack(alignment: .leading, spacing: 7) {
                                                Text("\(reading.target.shortName)（\(reading.measuredPoints.count) 個點）")
                                                    .font(.system(size: 11, weight: .semibold))
                                                    .foregroundColor(.secondary)

                                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], spacing: 8) {
                                                    ForEach(reading.measuredPoints) { point in
                                                        VStack(alignment: .leading, spacing: 4) {
                                                            HStack(alignment: .lastTextBaseline, spacing: 6) {
                                                                Text(point.name)
                                                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                                    .lineLimit(2)
                                                                Spacer(minLength: 4)
                                                                Text(String(format: "%.1f °C", point.temperatureCelsius))
                                                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                                            }
                                                            Text(point.source)
                                                                .font(.system(size: 9))
                                                                .foregroundColor(.secondary)
                                                        }
                                                        .padding(.horizontal, 9)
                                                        .padding(.vertical, 7)
                                                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                                                        .cornerRadius(8)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "list.bullet.rectangle")
                                    Text("具名實測點明細（\(fanVM.measuredSensorPointCount)）")
                                }
                                .font(.system(size: 12, weight: .bold))
                            }
                        }
                    }
                }

                // 2. Real-time Fan Speed Tachometers
                GlassCard(title: "風扇實際讀回值 (Actual RPM Readback)", iconName: "fan.fill", accentColor: .blue) {
                    VStack(spacing: 14) {
                        HStack(spacing: 24) {
                            if fanVM.fanStatuses.isEmpty {
                                Text(fanVM.helperCapability.localizedDescription)
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
                                            Text("實際讀回 0 RPM；不推論物理停轉原因")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("實際 \(fan.currentRPM) RPM · 目標 \(fan.targetRPM) RPM")
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
                                Text("目前查看的溫度來源：\(fanVM.selectedSensorTarget.displayName)")
                                    .font(.system(size: 13, weight: .bold))
                                Text(fanVM.selectedSensorTarget.description)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Menu {
                                ForEach(fanVM.measuredSensorTargets) { target in
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
                                    Text("更換查看來源")
                                }
                                .font(.system(size: 11))
                            }
                            .menuStyle(.borderlessButton)
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .cornerRadius(8)

                        Divider()

                        Text("溫度閉迴路只會在選定元件有可歸屬的控制等級感測器時啟用：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        if !fanVM.hasMeasuredTemperatureForSelectedTarget {
                            Label("此基準沒有可歸屬的實測溫度；溫控策略已停用，僅可使用原廠 Auto 或經讀回驗證的手動目標 RPM。", systemImage: "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.orange)
                        }

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
                                .disabled(requiresMeasuredTemperature(mode) && !fanVM.hasMeasuredTemperatureForSelectedTarget)
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

                            if let range = fanVM.supportedManualRPMRange {
                                Slider(value: $fanVM.customRPM, in: range, step: 100)
                                    .tint(.accentColor)

                                HStack {
                                    Text("\(Int(range.lowerBound)) RPM（硬體讀回下限）").font(.caption).foregroundColor(.secondary)
                                    Spacer()
                                    Button("套用自訂轉速") {
                                        fanVM.applyCustomRPM()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    Spacer()
                                    Text("\(Int(range.upperBound)) RPM（硬體讀回上限）").font(.caption).foregroundColor(.secondary)
                                }
                            } else {
                                Label("風扇數量或硬體 RPM 範圍不可取得；手動寫入已停用", systemImage: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundColor(.orange)
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
                                if let temperature = dashboardVM.batteryThermalSnapshot.batteryTemperatureCelsius {
                                    HStack {
                                        Text("電池硬體感測器溫度:").foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.1f °C（AppleSmartBattery 實測）", temperature)).bold()
                                    }
                                }

                                if let power = dashboardVM.batteryThermalSnapshot.powerWattage {
                                    HStack {
                                        Text("電池端即時功率:").foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.2f W（電池端實測）", power)).bold()
                                    }
                                }

                                if let health = dashboardVM.batteryThermalSnapshot.healthPercentage {
                                    HStack {
                                        Text("電池健康度:").foregroundColor(.secondary)
                                        Spacer()
                                        Text(String(format: "%.0f%%", health)).bold()
                                    }
                                }

                                if let cycles = dashboardVM.batteryThermalSnapshot.cycleCount {
                                    HStack {
                                        Text("電池循環次數:").foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(cycles) 次").bold()
                                    }
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

    private func requiresMeasuredTemperature(_ mode: FanMode) -> Bool {
        switch mode {
        case .quiet, .balanced, .maxCooling: return true
        case .automatic, .custom: return false
        }
    }
}
