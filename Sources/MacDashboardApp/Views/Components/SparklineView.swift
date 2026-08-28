import SwiftUI

public struct SparklineView: View {
    let data: [Double]
    let lineColor: Color
    let maxValue: Double?

    public init(
        data: [Double],
        lineColor: Color = .blue,
        fillColor: Color = .blue.opacity(0.15),
        maxValue: Double? = nil
    ) {
        self.data = data
        self.lineColor = lineColor
        self.maxValue = maxValue
    }

    public var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let maxVal = max(1.0, maxValue ?? (data.max() ?? 100.0))

            if data.count >= 2 {
                let stepX = w / CGFloat(data.count - 1)

                Path { path in
                    for (index, val) in data.enumerated() {
                        let normalized = CGFloat(min(maxVal, max(0.0, val)) / maxVal)
                        let y = h - (normalized * h)
                        let x = CGFloat(index) * stepX
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(lineColor, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
