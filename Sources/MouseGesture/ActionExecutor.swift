import AppKit
import ApplicationServices

enum ActionExecutor {
    static let eventTag: Int64 = 0x4D475354

    static func execute(_ action: GestureAction, preferences: Preferences, targetPID: pid_t) -> String {
        guard action != .none else { return "此轨迹未绑定操作" }
        guard AXIsProcessTrusted() else { return "辅助功能权限不可用" }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            return "前台应用已切换，本次手势已取消"
        }
        if action == .closeWindow { return closeWindow(pid: targetPID) }
        let shortcut = preferences.shortcut(for: action)
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            return "无法创建快捷键事件"
        }
        for event in [down, up] {
            event.flags = CGEventFlags(rawValue: shortcut.modifiers)
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
            // Session events reach system shortcuts as well as the active application.
            event.post(tap: .cgSessionEventTap)
        }
        return "已发送：\(action.title)（\(shortcut.label)）"
    }

    private static func closeWindow(pid: pid_t) -> String {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.3)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return "当前应用没有可关闭的窗口" }
        let element = unsafeBitCast(window, to: AXUIElement.self)
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return "当前窗口未提供关闭按钮" }
        let result = AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString)
        return result == .success ? "已请求关闭当前窗口" : "当前窗口拒绝关闭操作"
    }
}
