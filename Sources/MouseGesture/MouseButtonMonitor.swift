import AppKit

// Own the entire intercepted press, even if it is cancelled before mouse-up.
final class MouseButtonMonitor {
    var onClick: ((MouseButton, KeyboardShortcut, pid_t) -> Void)?
    var suspended = false { didSet { if suspended { cancel() } } }
    private let preferences: Preferences
    private let frontmostApplication: () -> NSRunningApplication?
    private var generation = UUID()
    private var applicationObserver: NSObjectProtocol?
    private struct Press {
        var button: MouseButton
        var binding: MouseButtonBinding
        var pid: pid_t
        var origin: CGPoint
        var cancelled = false
    }
    private var presses: [Int64: Press] = [:]

    init(preferences: Preferences, frontmostApplication: @escaping () -> NSRunningApplication?) {
        self.preferences = preferences
        self.frontmostApplication = frontmostApplication
        applicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.cancel() }
    }

    deinit {
        if let applicationObserver { NSWorkspace.shared.notificationCenter.removeObserver(applicationObserver) }
    }

    func cancel() {
        generation = UUID()
        for number in Array(presses.keys) { presses[number]?.cancelled = true }
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        guard [.otherMouseDown, .otherMouseDragged, .otherMouseUp].contains(type),
              event.getIntegerValueField(.eventSourceUserData) != ActionExecutor.eventTag else { return false }
        let number = event.getIntegerValueField(.mouseEventButtonNumber)
        let app = frontmostApplication()
        if type == .otherMouseDown {
            presses[number] = nil
            guard number != preferences.triggerButton, preferences.enabled, !suspended, !preferences.excludes(app?.bundleIdentifier),
                  let pid = app?.processIdentifier,
                  let button = MouseButton.allCases.first(where: { preferences.mouseBinding(for: $0, bundleID: app?.bundleIdentifier).buttonNumber == number }),
                  preferences.mouseBinding(for: button, bundleID: app?.bundleIdentifier).shortcut != nil else { return false }
            presses[number] = Press(button: button, binding: preferences.mouseBinding(for: button, bundleID: app?.bundleIdentifier),
                                    pid: pid, origin: event.location)
            return true
        }
        guard var press = presses[number] else { return false }
        if !preferences.enabled || suspended || app?.processIdentifier != press.pid
            || preferences.excludes(app?.bundleIdentifier)
            || preferences.mouseBinding(for: press.button, bundleID: app?.bundleIdentifier) != press.binding
            || hypot(event.location.x - press.origin.x, event.location.y - press.origin.y) > 6 {
            press.cancelled = true
        }
        if type == .otherMouseDragged {
            presses[number] = press
            return true
        }
        presses[number] = nil
        guard !press.cancelled, let shortcut = press.binding.shortcut else { return true }
        let session = generation
        // Shortcut posting and UI updates stay outside the synchronous event tap.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == session, self.preferences.enabled, !self.suspended,
                  self.frontmostApplication()?.processIdentifier == press.pid,
                  !self.preferences.excludes(self.frontmostApplication()?.bundleIdentifier),
                  self.preferences.mouseBinding(for: press.button, bundleID: self.frontmostApplication()?.bundleIdentifier) == press.binding else { return }
            self.onClick?(press.button, shortcut, press.pid)
        }
        return true
    }
}
