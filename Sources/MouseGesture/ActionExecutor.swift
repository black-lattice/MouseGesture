import AppKit
import ApplicationServices

enum ActionExecutor {
    static let eventTag: Int64 = 0x4D475354
    typealias ShortcutSender = (KeyboardShortcut, String, pid_t?) -> String

    @MainActor
    static func execute(_ action: GestureAction, preferences: Preferences, target: GestureTarget,
                        isCurrent: () -> Bool,
                        permissionCheck: () -> Bool = { AXIsProcessTrusted() },
                        sendShortcut: ShortcutSender = { send($0, title: $1, targetPID: $2) }) async -> String {
        guard action != .none else { return "此轨迹未绑定操作" }
        guard permissionCheck() else { return "辅助功能权限不可用" }
        guard isCurrent() else { return "手势已取消" }
        if !action.requiresTargetWindow, let shortcut = preferences.shortcut(for: action) {
            // Global actions must not activate windows or exit Show Desktop first.
            return sendShortcut(shortcut, action.title, nil)
        }
        guard target.isAvailable else { return "手势目标窗口已失效，本次操作已取消" }
        guard action.isAvailable(in: target.bundleIdentifier) else {
            return "请在访达窗口中使用“\(action.title)”"
        }
        if action == .closeWindow, let window = target.window { return closeWindow(window) }
        guard let shortcut = preferences.shortcut(for: action) else { return "此功能未设置快捷键" }
        return await send(shortcut, title: action.title, target: target, isCurrent: isCurrent,
                          sendShortcut: sendShortcut)
    }

    @MainActor
    static func execute(_ action: CustomAction, target: GestureTarget, isCurrent: () -> Bool) async -> String {
        await send(action.shortcut, title: action.name, target: target, isCurrent: isCurrent)
    }

    @MainActor
    private static func send(_ shortcut: KeyboardShortcut, title: String, target: GestureTarget,
                             isCurrent: () -> Bool,
                             sendShortcut: ShortcutSender = { send($0, title: $1, targetPID: $2) }) async -> String {
        guard AXIsProcessTrusted() else { return "辅助功能权限不可用" }
        guard await target.focus(while: isCurrent), isCurrent(), target.isFocused else {
            return "未能聚焦手势目标窗口，本次操作已取消"
        }
        return sendShortcut(shortcut, title, target.pid)
    }

    static func send(_ shortcut: KeyboardShortcut, title: String, targetPID: pid_t?) -> String {
        guard AXIsProcessTrusted() else { return "辅助功能权限不可用" }
        if let targetPID, NSWorkspace.shared.frontmostApplication?.processIdentifier != targetPID {
            return "前台应用已切换，本次手势已取消"
        }
        guard let events = makeShortcutEvents(shortcut) else { return "无法创建快捷键事件" }
        // Session events reach system shortcuts as well as the active application.
        events.forEach { $0.post(tap: .cgSessionEventTap) }
        return "已发送：\(title)（\(shortcut.label)）"
    }

    static func makeShortcutEvents(_ shortcut: KeyboardShortcut) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) else {
            return nil
        }
        for event in [down, up] {
            // F-keys and arrows carry intrinsic flags required by system shortcuts.
            let keyFlags = event.flags.intersection([.maskSecondaryFn, .maskNumericPad])
            event.flags = CGEventFlags(rawValue: shortcut.modifiers).union(keyFlags)
            event.setIntegerValueField(.eventSourceUserData, value: eventTag)
        }
        return [down, up]
    }

    private static func closeWindow(_ element: AXUIElement) -> String {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return "手势目标窗口未提供关闭按钮" }
        let result = AXUIElementPerformAction(unsafeBitCast(button, to: AXUIElement.self), kAXPressAction as CFString)
        return result == .success ? "已请求关闭手势所在窗口" : "手势目标窗口拒绝关闭操作"
    }
}
