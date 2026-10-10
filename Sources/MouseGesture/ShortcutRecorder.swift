import AppKit
import ApplicationServices

// Keep the full key press inside the recorder, including repeats and key-up.
struct ShortcutCapture {
    private var pressed = Set<Int64>()
    private var candidate: CGEvent?

    mutating func consume(type: CGEventType, event: CGEvent) -> (swallow: Bool, completed: CGEvent?) {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyDown {
            let firstPress = pressed.insert(code).inserted
            if firstPress && candidate == nil && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                candidate = event.copy()
            }
            return (true, nil)
        }
        if type == .keyUp, pressed.remove(code) != nil {
            guard pressed.isEmpty else { return (true, nil) }
            let result = candidate
            candidate = nil
            return (true, result)
        }
        return (false, nil)
    }
}

final class ShortcutRecorder {
    private let usesSystemCapture: Bool
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var localMonitor: Any?
    private var capture = ShortcutCapture()
    private var generation = UUID()
    private var onEvent: ((NSEvent) -> Void)?
    private var onInterrupted: (() -> Void)?

    init(usesSystemCapture: Bool = true) { self.usesSystemCapture = usesSystemCapture }

    func start(onInterrupted: @escaping () -> Void, onEvent: @escaping (NSEvent) -> Void) -> Bool {
        stop()
        self.onEvent = onEvent
        self.onInterrupted = onInterrupted
        // Isolated tests send local events without installing a system-wide tap.
        if !usesSystemCapture {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                onEvent(event)
                return nil
            }
            return localMonitor != nil
        }
        guard AXIsProcessTrusted() else { stop(); return false }
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let recorder = Unmanaged<ShortcutRecorder>.fromOpaque(context).takeUnretainedValue()
            return recorder.handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop()
            return false
        }
        self.tap = tap
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        generation = UUID()
        onEvent = nil
        onInterrupted = nil
        capture = ShortcutCapture()
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        localMonitor = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput || !NSApp.isActive || NSApp.keyWindow == nil {
            let interrupted = onInterrupted
            stop()
            let stoppedSession = generation
            DispatchQueue.main.async { [weak self] in
                guard self?.generation == stoppedSession else { return }
                interrupted?()
            }
            return pass
        }
        guard event.getIntegerValueField(.eventSourceUserData) != ActionExecutor.eventTag else { return pass }
        let result = capture.consume(type: type, event: event)
        if let completed = result.completed {
            let session = generation
            // Do not publish UI changes or remove the tap inside its synchronous callback.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == session, let event = NSEvent(cgEvent: completed) else { return }
                self.onEvent?(event)
            }
        }
        return result.swallow ? nil : pass
    }

    deinit { stop() }
}
