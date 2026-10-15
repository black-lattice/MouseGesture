import AppKit
import ApplicationServices

struct GestureTarget {
    let pid: pid_t
    let window: AXUIElement?
    var bundleIdentifier: String? { NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }

    static func at(_ point: CGPoint) -> GestureTarget? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.1)
        defer { AXUIElementSetMessagingTimeout(system, 0) }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
              let hit else { return nil }
        AXUIElementSetMessagingTimeout(hit, 0.1)
        let window: AXUIElement?
        if attribute(kAXRoleAttribute, of: hit) as? String == kAXWindowRole {
            window = hit
        } else if let value = attribute(kAXWindowAttribute, of: hit),
                  CFGetTypeID(value) == AXUIElementGetTypeID() {
            window = unsafeBitCast(value, to: AXUIElement.self)
        } else {
            // Finder's desktop may expose an application element without a window.
            window = nil
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(window ?? hit, &pid) == .success, pid > 0 else { return nil }
        if let window { AXUIElementSetMessagingTimeout(window, 0.1) }
        return GestureTarget(pid: pid, window: window)
    }

    var isAvailable: Bool {
        guard let window, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return false }
        return Self.attribute(kAXRoleAttribute, of: window) as? String == kAXWindowRole
    }

    var isFocused: Bool {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.1)
        return matches(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                       focusedWindow: Self.attribute(kAXFocusedWindowAttribute, of: application))
    }

    func matches(frontmostPID: pid_t?, focusedWindow: CFTypeRef?) -> Bool {
        guard let window, frontmostPID == pid, let focusedWindow,
              CFGetTypeID(focusedWindow) == AXUIElementGetTypeID() else { return false }
        return CFEqual(window, focusedWindow)
    }

    @MainActor
    func focus(while isCurrent: () -> Bool) async -> Bool {
        guard let window, isCurrent(), isAvailable else { return false }
        if isFocused { return true }
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        if #available(macOS 14, *) {
            app.activate(options: [])
        } else {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        return await Self.waitForFocus(while: isCurrent, isAvailable: { self.isAvailable },
                                       isFocused: { self.isFocused })
    }

    @MainActor
    private static func waitForFocus(while isCurrent: () -> Bool, isAvailable: () -> Bool,
                                     isFocused: () -> Bool,
                                     pause: () async throws -> Void = { try await Task.sleep(nanoseconds: 50_000_000) }) async -> Bool {
        // Activation is asynchronous. Never send a shortcut until this exact window is focused.
        for attempt in 0...20 {
            guard isCurrent(), isAvailable() else { return false }
            if isFocused() { return isCurrent() }
            guard attempt < 20 else { return false }
            do { try await pause() } catch { return false }
        }
        return false
    }

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
