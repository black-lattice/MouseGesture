import SwiftUI
import AppKit
import GestureCore

struct GestureRecordingView: View {
    let action: GestureAction
    @ObservedObject var preferences: Preferences
    let onFinish: () -> Void
    @State private var candidate: [Direction]?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("在下方区域按住\(preferences.triggerTitle)绘制，松开预览，再点击保存。录制期间不执行任何手势操作。")
                .font(.callout).foregroundStyle(.secondary)
            GestureRecordingPad(minimumLength: preferences.minimumLength, triggerButton: preferences.triggerButton, onStart: {
                candidate = nil
                error = nil
            }, onComplete: { directions in
                candidate = directions
                if let directions {
                    error = preferences.conflict(for: directions, action: action).map {
                        "此手势已用于“\($0)”，请重新绘制，或先清除该功能的手势。"
                    }
                } else {
                    error = "未识别到有效手势。请画清晰的直线或折线，总长度至少 \(Int(preferences.minimumLength)) 点，最多四段。"
                }
            }, onCancel: onFinish)
            .frame(height: 320)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
            .accessibilityLabel("\(action.title)的手势录制区域")
            if let error {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            } else {
                Text(candidate.map { "识别结果：" + $0.map(\.arrow).joined(separator: " ") } ?? "等待绘制 · Esc 取消")
                    .font(.callout)
            }
            HStack {
                Button("取消") { onFinish() }
                Spacer()
                Button("保存手势") {
                    guard let candidate else { return }
                    if preferences.bind(candidate, to: action) { onFinish() }
                    else { error = "此手势已被其他功能使用，请重新绘制。" }
                }.disabled(candidate == nil || error != nil)
            }
        }
        .onExitCommand { onFinish() }
    }
}

struct GestureRecordingPad: NSViewRepresentable {
    let minimumLength: Double
    var triggerButton: Int64 = 1
    let onStart: () -> Void
    let onComplete: ([Direction]?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecordingPadView { RecordingPadView() }

    func updateNSView(_ view: RecordingPadView, context: Context) {
        view.minimumLength = minimumLength
        view.triggerButton = triggerButton
        view.onStart = onStart
        view.onComplete = onComplete
        view.onCancel = onCancel
    }
}

final class RecordingPadView: NSView {
    var minimumLength: Double = 50
    var triggerButton: Int64 = 1
    var onStart: (() -> Void)?
    var onComplete: (([Direction]?) -> Void)?
    var onCancel: (() -> Void)?
    private var stroke: Stroke?
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        stroke = Stroke(start: convert(event.locationInWindow, from: nil))
        onStart?()
        needsDisplay = true
    }

    override func rightMouseDragged(with event: NSEvent) {
        append(event)
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        guard stroke != nil else { return }
        append(event)
        onComplete?(stroke?.recognize(minimumLength: minimumLength))
        needsDisplay = true
    }

    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == triggerButton { rightMouseDown(with: event) }
        else { super.otherMouseDown(with: event) }
    }
    override func otherMouseDragged(with event: NSEvent) {
        if event.buttonNumber == triggerButton { rightMouseDragged(with: event) }
        else { super.otherMouseDragged(with: event) }
    }
    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == triggerButton { rightMouseUp(with: event) }
        else { super.otherMouseUp(with: event) }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
        else { super.keyDown(with: event) }
    }

    private func append(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !bounds.contains(point) { stroke?.cancel() }
        stroke?.append(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let points = stroke?.points, let first = points.first else { return }
        let path = NSBezierPath()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: first)
        points.dropFirst().forEach { path.line(to: $0) }
        NSColor.systemTeal.setStroke()
        path.stroke()
    }
}
