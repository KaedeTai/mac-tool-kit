import SwiftUI

public struct StatBadge: View {
    let text: String
    let iconName: String?
    let color: Color

    public init(text: String, iconName: String? = nil, color: Color = .blue) {
        self.text = text
        self.iconName = iconName
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.12))
        .foregroundColor(color)
        .clipShape(Capsule())
    }
}
