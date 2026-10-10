import AppKit

final class TrailOverlay {
    private var panels: [NSPanel] = []
    private var views: [TrailView] = []

    func show(points: [CGPoint], label: String) {
        if panels.isEmpty { prepare() }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        for (panel, view) in zip(panels, views) {
            view.points = points.map { CGPoint(x: $0.x - panel.frame.minX, y: primaryTop - $0.y - panel.frame.minY) }
            view.label = label
            view.needsDisplay = true
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panels.forEach {
            // Remove the trail before an action starts a Space transition.
            $0.alphaValue = 0
            $0.orderOut(nil)
        }
        panels.removeAll()
        views.removeAll()
    }

    private func prepare() {
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.animationBehavior = .none
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = TrailView(frame: CGRect(origin: .zero, size: screen.frame.size))
            panel.contentView = view
            panels.append(panel)
            views.append(view)
        }
    }
}

private final class TrailView: NSView {
    var points: [CGPoint] = []
    var label = ""

    override func draw(_ dirtyRect: NSRect) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = 4
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        NSColor.systemTeal.setStroke()
        path.stroke()
        guard let last = points.last, bounds.contains(last) else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .medium),
                                                        .foregroundColor: NSColor.white]
        let size = (label as NSString).size(withAttributes: attributes)
        let box = CGRect(x: min(max(last.x + 18, 8), bounds.width - size.width - 32),
                         y: min(max(last.y - 44, 8), bounds.height - 40), width: size.width + 24, height: 32)
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        (label as NSString).draw(at: CGPoint(x: box.minX + 12, y: box.minY + 7), withAttributes: attributes)
    }
}
