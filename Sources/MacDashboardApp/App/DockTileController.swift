import AppKit

/// Draws a live CPU / RAM / GPU meter into the Dock icon, in the spirit of
/// Activity Monitor's "Show CPU Usage" Dock icon — but with all three bars
/// visible at once.
@MainActor
final class DockTileController {

    static let shared = DockTileController()

    private static let defaultsKey = "dockTileUsageEnabled"

    private let gaugeView = DockGaugeView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))

    private(set) var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.defaultsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: Self.defaultsKey) }
    }

    private init() {}

    func activate() {
        apply()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        apply()
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Feed fresh values in. Cheap: it only redraws when something moved
    /// enough to be visible at Dock resolution.
    func update(cpu: Double, ram: Double, gpu: Double) {
        guard isEnabled else { return }
        let changed = gaugeView.setValues(cpu: cpu, ram: ram, gpu: gpu)
        if changed {
            NSApp.dockTile.display()
        }
    }

    private func apply() {
        if isEnabled {
            NSApp.dockTile.contentView = gaugeView
        } else {
            NSApp.dockTile.contentView = nil
        }
        NSApp.dockTile.display()
    }
}

// MARK: - Gauge View

final class DockGaugeView: NSView {

    private var cpu: Double = 0
    private var ram: Double = 0
    private var gpu: Double = 0

    private enum Palette {
        static let background = NSColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.94)
        static let border     = NSColor(white: 1.0, alpha: 0.14)
        static let track      = NSColor(white: 1.0, alpha: 0.13)
        static let label      = NSColor(white: 1.0, alpha: 0.62)
        static let cpu        = NSColor(srgbRed: 0.24, green: 0.66, blue: 1.00, alpha: 1.0)  // blue
        static let ram        = NSColor(srgbRed: 0.68, green: 0.40, blue: 0.98, alpha: 1.0)  // purple
        static let gpu        = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.10, alpha: 1.0)  // amber
        static let hot        = NSColor(srgbRed: 1.00, green: 0.27, blue: 0.30, alpha: 1.0)  // red >= 90%
    }

    /// Returns true when the change is big enough to be worth a redraw.
    func setValues(cpu: Double, ram: Double, gpu: Double) -> Bool {
        let c = cpu.clamped(), r = ram.clamped(), g = gpu.clamped()
        let moved = abs(c - self.cpu) >= 0.5 || abs(r - self.ram) >= 0.5 || abs(g - self.gpu) >= 0.5
        self.cpu = c; self.ram = r; self.gpu = g
        if moved { needsDisplay = true }
        return moved
    }

    override func draw(_ dirtyRect: NSRect) {
        let side = min(bounds.width, bounds.height)
        let scale = side / 128.0
        func s(_ v: CGFloat) -> CGFloat { v * scale }

        // Card background
        let card = NSRect(x: s(4), y: s(4), width: s(120), height: s(120))
        let cardPath = NSBezierPath(roundedRect: card, xRadius: s(27), yRadius: s(27))
        Palette.background.setFill()
        cardPath.fill()
        Palette.border.setStroke()
        cardPath.lineWidth = s(1.5)
        cardPath.stroke()

        let barWidth = s(20)
        let gap = s(12)
        let totalWidth = barWidth * 3 + gap * 2
        let startX = (bounds.width - totalWidth) / 2
        let barBottom = s(30)
        let barHeight = s(82)

        let entries: [(value: Double, color: NSColor, label: String)] = [
            (cpu, Palette.cpu, "C"),
            (ram, Palette.ram, "R"),
            (gpu, Palette.gpu, "G")
        ]

        for (index, entry) in entries.enumerated() {
            let x = startX + CGFloat(index) * (barWidth + gap)
            let track = NSRect(x: x, y: barBottom, width: barWidth, height: barHeight)
            let radius = barWidth / 2
            let trackPath = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)

            Palette.track.setFill()
            trackPath.fill()

            let fraction = CGFloat(entry.value / 100.0)
            if fraction > 0.005 {
                NSGraphicsContext.saveGraphicsState()
                trackPath.addClip()

                let filledHeight = max(barWidth, barHeight * fraction)
                let fillRect = NSRect(x: x, y: barBottom, width: barWidth, height: filledHeight)
                let top = entry.value >= 90 ? Palette.hot : entry.color
                let bottom = top.blended(withFraction: 0.35, of: .black) ?? top
                let gradient = NSGradient(starting: bottom, ending: top)
                gradient?.draw(in: fillRect, angle: 90)

                NSGraphicsContext.restoreGraphicsState()
            }

            // Channel letter beneath the bar
            let font = NSFont.systemFont(ofSize: s(15), weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: Palette.label
            ]
            let text = entry.label as NSString
            let size = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(x: x + (barWidth - size.width) / 2, y: s(9)),
                withAttributes: attributes
            )
        }
    }
}

private extension Double {
    func clamped() -> Double {
        if isNaN || isInfinite { return 0 }
        return Swift.min(100, Swift.max(0, self))
    }
}
