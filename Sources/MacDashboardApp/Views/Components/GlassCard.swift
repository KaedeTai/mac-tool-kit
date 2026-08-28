import SwiftUI

public struct GlassCard<Content: View>: View {
    let title: String?
    let iconName: String?
    let accentColor: Color
    let content: Content

    public init(
        title: String? = nil,
        iconName: String? = nil,
        accentColor: Color = .accentColor,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.iconName = iconName
        self.accentColor = accentColor
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title = title {
                HStack(spacing: 8) {
                    if let iconName = iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(accentColor)
                    }
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.65))
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Material.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
    }
}
