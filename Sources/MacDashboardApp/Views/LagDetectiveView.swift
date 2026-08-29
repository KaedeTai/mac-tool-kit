import SwiftUI
import MacToolKitCore

public struct LagDetectiveView: View {
    @ObservedObject var dashboardVM: DashboardViewModel
    @ObservedObject var lagVM: LagDetectiveViewModel
    @State private var pendingDestructiveAction: RemediationAction?

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header Hero
                GlassCard(accentColor: .accentColor) {
                    HStack(spacing: 24) {
                        // Circular Health Score
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.15), lineWidth: 12)
                                .frame(width: 110, height: 110)

                            Circle()
                                .trim(from: 0.0, to: CGFloat(Double(lagVM.report.healthScore) / 100.0))
                                .stroke(
                                    scoreColor(for: lagVM.report.healthScore),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 110, height: 110)
                                .animation(.easeInOut, value: lagVM.report.healthScore)

                            VStack(spacing: 2) {
                                Text(lagVM.report.severity == .unknown ? "--" : "\(lagVM.report.healthScore)")
                                    .font(.system(size: 32, weight: .bold, design: .rounded))
                                    .foregroundColor(scoreColor(for: lagVM.report.healthScore))
                                Text("規則分數（衍生）")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                StatBadge(
                                    text: lagVM.report.severity.rawValue,
                                    iconName: lagVM.report.severity.systemIcon,
                                    color: scoreColor(for: lagVM.report.healthScore)
                                )

                                if let time = lagVM.lastDiagnosisTime {
                                    Text("上次診斷: \(time.formatted(date: .omitted, time: .standard))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Text(lagVM.report.summary)
                                .font(.system(size: 14))
                                .foregroundColor(.primary)
                                .lineSpacing(3)

                            Button {
                                lagVM.runDiagnosis(from: dashboardVM)
                            } label: {
                                HStack(spacing: 6) {
                                    if lagVM.isAnalyzing {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    Text(lagVM.isAnalyzing ? "正在深入掃描中..." : "立即重新診斷 Lag")
                                }
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .disabled(lagVM.isAnalyzing)
                        }
                    }
                }

                // Action Feedback Message
                if let feedback = lagVM.actionFeedbackMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(feedback)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(10)
                }

                // Suggested Remediation Actions
                if !lagVM.report.suggestedActions.isEmpty {
                    GlassCard(title: "建議修復動作 (One-Click Remedies)", iconName: "bolt.badge.checkmark.fill", accentColor: .green) {
                        VStack(spacing: 12) {
                            ForEach(lagVM.report.suggestedActions) { action in
                                HStack(spacing: 14) {
                                    Image(systemName: action.iconName)
                                        .font(.system(size: 20))
                                        .foregroundColor(action.isDestructive ? .red : .accentColor)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(action.title)
                                            .font(.system(size: 13, weight: .bold))
                                        Text(action.explanation)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Button {
                                        if action.isDestructive {
                                            pendingDestructiveAction = action
                                        } else {
                                            lagVM.executeAction(action, dashboardVM: dashboardVM)
                                        }
                                    } label: {
                                        Text(action.buttonTitle)
                                            .font(.system(size: 12, weight: .semibold))
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(action.isDestructive ? Color.red : Color.accentColor)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                .cornerRadius(10)
                            }
                        }
                    }
                }

                // Identified Causes Breakdown
                GlassCard(title: "詳細卡頓瓶頸分析原因 (Identified Causes)", iconName: "magnifyingglass.circle.fill", accentColor: .orange) {
                    if lagVM.report.causes.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.title3)
                            Text("目前規則未找到明顯瓶頸；不代表已排除所有卡頓原因。")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(lagVM.report.causes) { cause in
                                HStack(spacing: 14) {
                                    Image(systemName: cause.iconName)
                                        .font(.system(size: 18))
                                        .foregroundColor(cause.isMajor ? .red : .orange)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Text(cause.title)
                                                .font(.system(size: 13, weight: .bold))
                                            Text("[\(cause.category)]")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(cause.isMajor ? .red : .orange)
                                        }
                                        Text(cause.detail)
                                            .font(.system(size: 12))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            if lagVM.lastDiagnosisTime == nil {
                lagVM.runDiagnosis(from: dashboardVM)
            }
        }
        .confirmationDialog(
            "確認執行會結束行程的修復？",
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDestructiveAction {
                Button(action.buttonTitle, role: .destructive) {
                    lagVM.executeAction(action, dashboardVM: dashboardVM)
                    pendingDestructiveAction = nil
                }
                Button("取消", role: .cancel) { pendingDestructiveAction = nil }
            }
        } message: {
            if let action = pendingDestructiveAction {
                Text(action.explanation)
            }
        }
    }

    private func scoreColor(for score: Int) -> Color {
        if lagVM.report.severity == .unknown { return .secondary }
        if score >= 85 {
            return .green
        } else if score >= 65 {
            return .blue
        } else if score >= 40 {
            return .orange
        } else {
            return .red
        }
    }
}
