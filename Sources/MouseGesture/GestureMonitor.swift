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
        strokeID = UUID()
        lastDraw = 0
        if stroke != nil { swallowUntilUp = true }
        stroke = nil
        savedDown = nil
        overlay.hide()
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
            savedDown = event.copy()
            return nil
        }
        if swallowUntilUp {
            if type == .rightMouseUp { swallowUntilUp = false }
            return nil
        }
        guard var current = stroke else { return pass }
        if !preferences.enabled || suspended || frontmostApplication()?.processIdentifier != targetPID {
            cancel()
            if type == .rightMouseUp { swallowUntilUp = false }
            return nil
        }
        current.append(event.location)
        stroke = current
        if type == .rightMouseDragged {
            let now = ProcessInfo.processInfo.systemUptime
            if current.isGesture, preferences.showTrail, now - lastDraw >= 1.0 / 60 {
                lastDraw = now
                let id = strokeID
                // Window work stays outside the synchronous event-tap callback.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.strokeID == id, self.stroke != nil else { return }
                    let directions = current.recognize(minimumLength: self.preferences.minimumLength)
                    let label = directions.map { sequence in
                        sequence.map(\.arrow).joined() + "  " + self.preferences.title(for: sequence)
                    } ?? "继续绘制 · 松开结束 · Esc 取消"
                    self.overlay.show(points: current.points, label: label)
                }
            }
            return nil
        }
        if type == .rightMouseUp {
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
