import AppKit

final class TrailOverlay {
    private var panels: [NSPanel] = []
    private var views: [TrailView] = []

    func show(points: [CGPoint], label: String) {
        if panels.isEmpty { prepare() }
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        for (panel, view) in zip(panels, views) {
            view.update(points: points.map {
                CGPoint(x: $0.x - panel.frame.minX, y: primaryTop - $0.y - panel.frame.minY)
            }, label: label)
            if view.drawingBounds.isEmpty {
                if panel.isVisible { panel.orderOut(nil) }
            } else if !panel.isVisible {
                // Paint the first frame before exposing the transparent window.
                panel.displayIfNeeded()
                panel.orderFrontRegardless()
            }
        }
    }

    func hide() {
        let hiddenPanels = panels
        let hiddenViews = views
        panels.removeAll()
        views.removeAll()
        hiddenPanels.forEach {
            // Remove the trail before an action starts a Space transition.
            $0.alphaValue = 0
            $0.orderOut(nil)
        }
        // Releasing NSPanels can be expensive; finish the action callback first.
        if !hiddenPanels.isEmpty {
            DispatchQueue.main.async { withExtendedLifetime((hiddenPanels, hiddenViews)) {} }
        }
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
    private(set) var points: [CGPoint] = []
    private var label = ""
    private var path = NSBezierPath()
    private var labelBox: CGRect?
    private var labelTextHeight: CGFloat = 0
    private(set) var drawingBounds = CGRect.null
    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 14, weight: .medium), .foregroundColor: NSColor.white
    ]

    // Return the invalidated area so isolated rendering tests can compare partial and full draws.
    @discardableResult
    func update(points: [CGPoint], label: String) -> CGRect {
        let pointsChanged = self.points != points
        guard pointsChanged || self.label != label else { return .null }
        let previousBounds = drawingBounds
        if pointsChanged {
            self.points = points
            path = NSBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            if let first = points.first {
                path.move(to: first)
                points.dropFirst().forEach { path.line(to: $0) }
            }
        }
        self.label = label
        labelBox = nil
        if !label.isEmpty, let last = points.last, bounds.contains(last) {
            let size = (label as NSString).size(withAttributes: Self.attributes)
            labelTextHeight = size.height
            // Names can contain line breaks; include the full text height in the box and dirty region.
            let height = max(32, ceil(size.height) + 14)
            labelBox = CGRect(x: min(max(last.x + 18, 8), bounds.width - size.width - 32),
                              y: min(max(last.y - height - 12, 8), max(8, bounds.height - height - 8)),
                              width: size.width + 24, height: height)
        }
        // Include stroke caps/antialiasing and the old label, so moving/shortening it leaves no residue.
        let trailBounds = points.count < 2 ? CGRect.null : path.bounds.insetBy(dx: -4, dy: -4)
        drawingBounds = trailBounds.union(labelBox?.insetBy(dx: -1, dy: -1) ?? .null).intersection(bounds)
        let dirty = previousBounds.union(drawingBounds).integral.intersection(bounds)
        if !dirty.isNull && !dirty.isEmpty { setNeedsDisplay(dirty) }
        return dirty
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSBezierPath(rect: dirtyRect).addClip()
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        NSColor.systemTeal.setStroke()
        path.stroke()
        guard let box = labelBox else { return }
        NSColor.black.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: box, xRadius: 8, yRadius: 8).fill()
        (label as NSString).draw(at: CGPoint(x: box.minX + 12, y: box.midY - labelTextHeight / 2),
                                withAttributes: Self.attributes)
    }
}
