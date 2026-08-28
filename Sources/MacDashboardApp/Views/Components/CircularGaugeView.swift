import SwiftUI

public struct CircularGaugeView: View {
    let percentage: Double
    let title: String
    let subtitle: String?
    let iconName: String
    let size: CGFloat

    public init(
        percentage: Double,
        title: String,
        subtitle: String? = nil,
        iconName: String = "gauge",
        colorGradient: [Color] = [.green, .orange, .red],
        size: CGFloat = 100
    ) {
        self.percentage = percentage
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.size = size
    }

    private var currentColor: Color {
        if percentage < 50 {
            return .green
        } else if percentage < 80 {
            return .orange
        } else {
            return .red
        }
    }

    public var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: size, height: size)

                Circle()
                    .trim(from: 0.0, to: CGFloat(min(1.0, max(0.0, percentage / 100.0))))
                    .stroke(
                        currentColor,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size, height: size)

                VStack(spacing: 2) {
                    Image(systemName: iconName)
                        .font(.system(size: size * 0.16, weight: .bold))
                        .foregroundColor(currentColor)

                    Text(String(format: "%.1f%%", percentage))
                        .font(.system(size: size * 0.20, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: size * 0.11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
