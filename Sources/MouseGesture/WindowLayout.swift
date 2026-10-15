import AppKit
import ApplicationServices

enum WindowLayout {
    static func frame(for action: GestureAction, window: CGRect, screens: [CGRect]) -> CGRect? {
        guard !screens.isEmpty else { return nil }
        let index = screens.indices.max { left, right in
            area(window.intersection(screens[left])) < area(window.intersection(screens[right]))
        } ?? 0
        let screen = screens[index]
        switch action {
        case .windowLeft: return CGRect(x: screen.minX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .windowRight: return CGRect(x: screen.midX, y: screen.minY, width: screen.width / 2, height: screen.height)
        case .windowMaximize: return screen
        case .windowCenter:
            let size = CGSize(width: min(window.width, screen.width), height: min(window.height, screen.height))
            return CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width, height: size.height)
        case .windowNextDisplay:
            guard screens.count > 1 else { return nil }
            let next = screens[(index + 1) % screens.count]
            let size = CGSize(width: min(window.width, next.width), height: min(window.height, next.height))
            let x = next.minX + (window.minX - screen.minX) / max(1, screen.width) * next.width
            let y = next.minY + (window.minY - screen.minY) / max(1, screen.height) * next.height
            return CGRect(x: min(max(x, next.minX), next.maxX - size.width),
                          y: min(max(y, next.minY), next.maxY - size.height), width: size.width, height: size.height)
        default: return nil
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.isNull ? 0 : rect.width * rect.height }

    static func apply(_ action: GestureAction, to window: AXUIElement) -> String {
        guard let original = readFrame(window) else { return "无法读取目标窗口的位置或大小" }
        var fullScreen: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen)
        guard fullScreen as? Bool != true else { return "请先退出全屏，再调整窗口布局" }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { screen -> CGRect in
            let rect = screen.visibleFrame
            return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
        guard let frame = frame(for: action, window: original, screens: screens) else {
            return "移动到另一块显示器需要至少两个显示器"
        }
        var positionSettable: DarwinBoolean = false
        var sizeSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable)
        AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable)
        guard positionSettable.boolValue, sizeSettable.boolValue else { return "此窗口不支持调整位置或大小" }
        var point = frame.origin
        var size = frame.size
        guard let pointValue = AXValueCreate(.cgPoint, &point), let sizeValue = AXValueCreate(.cgSize, &size) else {
            return "无法创建窗口布局参数"
        }
        let resize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let move = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, pointValue)
        // Some applications constrain size on the original display. Retry after moving.
        let finalResize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard resize == .success || finalResize == .success, move == .success else { return "目标应用未完整接受窗口布局请求" }
        guard let actual = readFrame(window), abs(actual.minX - frame.minX) < 3, abs(actual.minY - frame.minY) < 3,
              abs(actual.width - frame.width) < 3, abs(actual.height - frame.height) < 3 else {
            return "已请求：\(action.title)（应用可能限制窗口大小或延后更新）"
        }
        return "已完成：\(action.title)"
    }

    private static func readFrame(_ window: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
