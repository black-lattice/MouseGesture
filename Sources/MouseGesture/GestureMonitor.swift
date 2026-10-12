import AppKit
import ApplicationServices
import GestureCore

final class GestureMonitor {
    var onStatus: ((String) -> Void)?
    var onRecognized: (([Direction], pid_t) -> Void)?
    var suspended = false
    private let preferences: Preferences
    private let overlay = TrailOverlay()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var stroke: Stroke?
    private var savedDown: CGEvent?
    private var targetPID: pid_t = 0
    private var swallowUntilUp = false
    private var lastDraw: TimeInterval = 0
    private var drawPending = false
    private var lastDrawnPointCount = 0
    private var previewTimer: Timer?
    private var previewLabel = ""
    private var lastMotionPoint: CGPoint?
    private var strokeID = UUID()
    private var spaceObserver: NSObjectProtocol?
    private let frontmostApplication: () -> NSRunningApplication?
    var isRunning: Bool { tap != nil }

    init(preferences: Preferences,
         frontmostApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }) {
        self.preferences = preferences
        self.frontmostApplication = frontmostApplication
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    deinit {
        previewTimer?.invalidate()
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
    }

    func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown, .leftMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<GestureMonitor>.fromOpaque(context).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        cancel()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    func cancel() {
        cancelPreview()
        strokeID = UUID()
        lastDraw = 0
        drawPending = false
        lastDrawnPointCount = 0
        if stroke != nil { swallowUntilUp = true }
        stroke = nil
        savedDown = nil
        overlay.hide()
    }

    private func cancelPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        previewLabel = ""
        lastMotionPoint = nil
    }

    private func schedulePreview() {
        // Reuse one timer while moving instead of queuing work for every mouse event.
        if let previewTimer {
            previewTimer.fireDate = Date(timeIntervalSinceNow: 0.2)
            return
        }
        let id = strokeID
        let timer = Timer(timeInterval: 0.2, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.previewTimer = nil
            guard self.strokeID == id, let current = self.stroke else { return }
            guard self.preferences.enabled, !self.suspended,
                  self.frontmostApplication()?.processIdentifier == self.targetPID else {
                self.cancel()
                return
            }
            guard self.preferences.showTrail else { self.overlay.hide(); return }
            self.previewLabel = current.recognize(minimumLength: self.preferences.minimumLength).map { sequence in
                sequence.map(\.arrow).joined(separator: " ") + "  " + self.preferences.title(for: sequence)
            } ?? "未识别手势 · 继续绘制 · Esc 取消"
            self.lastDrawnPointCount = current.points.count
            self.overlay.show(points: current.points, label: self.previewLabel)
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            cancel()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        if event.getIntegerValueField(.eventSourceUserData) == ActionExecutor.eventTag { return pass }
        if type == .keyDown || type == .leftMouseDown {
            if stroke != nil {
                cancel()
                onStatus?("手势已取消")
                if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 { return nil }
            }
            return pass
        }
        if type == .rightMouseDown {
            // A fresh physical press also recovers from a missing mouse-up after sleep.
            swallowUntilUp = false
            cancel()
            swallowUntilUp = false
            let app = frontmostApplication()
            guard preferences.enabled, !suspended, !event.flags.contains(.maskAlternate),
                  !preferences.excludes(app?.bundleIdentifier) else { return pass }
            targetPID = app?.processIdentifier ?? 0
            stroke = Stroke(start: event.location)
            lastMotionPoint = event.location
            savedDown = event.copy()
            return nil
        }
        if swallowUntilUp {
            if type == .rightMouseUp { swallowUntilUp = false }
            return nil
        }
        guard stroke != nil else { return pass }
        if !preferences.enabled || suspended || frontmostApplication()?.processIdentifier != targetPID {
            cancel()
            if type == .rightMouseUp { swallowUntilUp = false }
            return nil
        }
        stroke?.append(event.location)
        if type == .rightMouseDragged {
            // Keep a visible hint stable under hand jitter. Compare against the fixed
            // pause point so a series of small movements still counts as resumed drawing.
            if let lastMotionPoint, event.location != lastMotionPoint,
               previewLabel.isEmpty || hypot(event.location.x - lastMotionPoint.x,
                                             event.location.y - lastMotionPoint.y) >= 3 {
                self.lastMotionPoint = event.location
                if !previewLabel.isEmpty {
                    previewLabel = ""
                    lastDrawnPointCount = 0
                    lastDraw = 0
                }
                if stroke?.isGesture == true, preferences.showTrail { schedulePreview() }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if stroke?.isGesture == true, preferences.showTrail, stroke?.points.count != lastDrawnPointCount,
               !drawPending, now - lastDraw >= 1.0 / 60 {
                drawPending = true
                lastDraw = now
                let id = strokeID
                // Window work stays outside the synchronous event-tap callback.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.strokeID == id else { return }
                    self.drawPending = false
                    guard let current = self.stroke, self.preferences.showTrail else { return }
                    self.lastDrawnPointCount = current.points.count
                    // Moving only draws; matching happens once the mouse has been still for 200 ms.
                    self.overlay.show(points: current.points, label: self.previewLabel)
                }
            }
            return nil
        }
        if type == .rightMouseUp, let current = stroke {
            cancelPreview()
            let down = savedDown
            let up = event.copy()
            let pid = targetPID
            let id = strokeID
            stroke = nil
            savedDown = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.strokeID == id else { return }
                self.overlay.hide()
                guard self.frontmostApplication()?.processIdentifier == pid else {
                    self.onStatus?("前台应用已切换，本次手势已取消")
                    return
                }
                if current.shouldReplayClick, let down, let up {
                    for replay in [down, up] {
                        replay.setIntegerValueField(.eventSourceUserData, value: ActionExecutor.eventTag)
                        replay.post(tap: .cgSessionEventTap)
                    }
                } else if let directions = current.recognize(minimumLength: self.preferences.minimumLength) {
                    self.onRecognized?(directions, pid)
                } else {
                    self.onStatus?("未识别手势，未执行操作")
                }
            }
            return nil
        }
        return pass
    }
}
