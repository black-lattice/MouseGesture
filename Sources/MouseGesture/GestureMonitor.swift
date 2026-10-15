import AppKit
import ApplicationServices
import GestureCore

final class GestureMonitor {
    var onStatus: ((String) -> Void)?
    var onRecognized: (([Direction], GestureTarget) -> Void)?
    var suspended = false { didSet { mouseButtons.suspended = suspended } }
    let mouseButtons: MouseButtonMonitor
    private let preferences: Preferences
    private let overlay = TrailOverlay()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var stroke: Stroke?
    private var savedDown: CGEvent?
    private var target: GestureTargetRequest?
    private var initialFrontmostPID: pid_t?
    private var swallowUntilUp = false
    private var lastDraw: TimeInterval = 0
    private var drawPending = false
    private var lastDrawnPointCount = 0
    private var previewTimer: Timer?
    private var previewLabel = ""
    private var lastMotionPoint: CGPoint?
    private var strokeID = UUID()
    private var spaceObserver: NSObjectProtocol?
    private var applicationObserver: NSObjectProtocol?
    private var lookupWork: DispatchWorkItem?
    private var awaitingAction = false
    private var expectedActivationPID: pid_t?
    private let frontmostApplication: () -> NSRunningApplication?
    private let rightButtonPressed: () -> Bool
    private let captureTarget: (CGPoint) -> GestureTargetRequest?
    private let lookupTarget: (GestureTargetRequest, @escaping (GestureTarget?) -> Void) -> DispatchWorkItem?
    private let postEvent: (CGEvent) -> Void
    private let workspaceNotifications: NotificationCenter
    var currentStrokeID: UUID { strokeID }
    var isRunning: Bool { tap != nil }

    init(preferences: Preferences,
         frontmostApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
         rightButtonPressed: @escaping () -> Bool = { CGEventSource.buttonState(.hidSystemState, button: .right) },
         captureTarget: @escaping (CGPoint) -> GestureTargetRequest? = GestureTargetRequest.capture,
         lookupTarget: @escaping (GestureTargetRequest, @escaping (GestureTarget?) -> Void) -> DispatchWorkItem? = GestureTargetRequest.lookup,
         postEvent: @escaping (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
         workspaceNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.preferences = preferences
        self.frontmostApplication = frontmostApplication
        self.rightButtonPressed = rightButtonPressed
        self.captureTarget = captureTarget
        self.lookupTarget = lookupTarget
        self.postEvent = postEvent
        self.workspaceNotifications = workspaceNotifications
        mouseButtons = MouseButtonMonitor(preferences: preferences, frontmostApplication: frontmostApplication)
        spaceObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
        applicationObserver = workspaceNotifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let self, self.stroke != nil || self.awaitingAction else { return }
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if self.stroke == nil, let expected = self.expectedActivationPID, app?.processIdentifier == expected { return }
            self.cancel()
            self.onStatus?("前台应用已切换，本次手势已取消")
        }
    }

    deinit {
        previewTimer?.invalidate()
        if let spaceObserver { workspaceNotifications.removeObserver(spaceObserver) }
        if let applicationObserver { workspaceNotifications.removeObserver(applicationObserver) }
        lookupWork?.cancel()
    }

    func start() -> Bool {
        if tap != nil { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.rightMouseDown, .rightMouseDragged, .rightMouseUp, .keyDown, .leftMouseDown,
                                    .otherMouseDown, .otherMouseDragged, .otherMouseUp]
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

    @discardableResult
    func beginExecution(targetPID: pid_t?) -> Bool {
        guard frontmostApplication()?.processIdentifier == initialFrontmostPID else { cancel(); return false }
        expectedActivationPID = targetPID
        return true
    }

    func finishExecution(strokeID: UUID) {
        guard self.strokeID == strokeID else { return }
        awaitingAction = false
        expectedActivationPID = nil
    }

    func cancel() {
        lookupWork?.cancel()
        lookupWork = nil
        awaitingAction = false
        expectedActivationPID = nil
        mouseButtons.cancel()
        cancelPreview()
        strokeID = UUID()
        lastDraw = 0
        drawPending = false
        lastDrawnPointCount = 0
        if stroke != nil { swallowUntilUp = true }
        stroke = nil
        savedDown = nil
        target = nil
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
            guard self.rightButtonPressed() else { return }
            guard self.preferences.enabled, !self.suspended,
                  self.frontmostApplication()?.processIdentifier == self.initialFrontmostPID else {
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
        if type == .otherMouseDown || type == .otherMouseDragged || type == .otherMouseUp {
            if type == .otherMouseDown { cancel() }
            return mouseButtons.handle(type: type, event: event) ? nil : pass
        }
        if type == .keyDown || type == .leftMouseDown {
            let wasDrawing = stroke != nil
            cancel()
            if wasDrawing {
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
            guard preferences.enabled, !suspended, !event.flags.contains(.maskAlternate),
                  let target = captureTarget(event.location),
                  !preferences.excludes(target.bundleIdentifier) else { return pass }
            self.target = target
            initialFrontmostPID = frontmostApplication()?.processIdentifier
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
        if !preferences.enabled || suspended || frontmostApplication()?.processIdentifier != initialFrontmostPID {
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
        if type == .rightMouseUp, let current = stroke, let target {
            cancelPreview()
            let down = savedDown
            let up = event.copy()
            let frontmostPID = initialFrontmostPID
            let id = strokeID
            stroke = nil
            savedDown = nil
            self.target = nil
            awaitingAction = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.strokeID == id else { return }
                self.overlay.hide()
                guard self.preferences.enabled, !self.suspended,
                      self.frontmostApplication()?.processIdentifier == frontmostPID else {
                    self.onStatus?("前台应用已切换，本次手势已取消")
                    return
                }
                if current.shouldReplayClick, let down, let up {
                    self.awaitingAction = false
                    for replay in [down, up] {
                        replay.setIntegerValueField(.eventSourceUserData, value: ActionExecutor.eventTag)
                        self.postEvent(replay)
                    }
                } else if let directions = current.recognize(minimumLength: self.preferences.minimumLength) {
                    let needsWindow = self.preferences.customAction(for: directions) != nil
                        || self.preferences.action(for: directions).requiresTargetWindow
                    if !needsWindow {
                        self.onRecognized?(directions, target.globalTarget)
                        return
                    }
                    self.lookupWork = self.lookupTarget(target) { [weak self] resolved in
                        guard let self, self.strokeID == id, self.preferences.enabled, !self.suspended else { return }
                        self.lookupWork = nil
                        guard self.frontmostApplication()?.processIdentifier == frontmostPID else {
                            self.cancel()
                            self.onStatus?("前台应用已切换，本次手势已取消")
                            return
                        }
                        guard let resolved else {
                            self.awaitingAction = false
                            self.onStatus?("无法确认手势起点窗口，本次操作已取消")
                            return
                        }
                        self.onRecognized?(directions, resolved)
                    }
                } else {
                    self.awaitingAction = false
                    self.onStatus?("未识别手势，未执行操作")
                }
            }
            return nil
        }
        return pass
    }
}
