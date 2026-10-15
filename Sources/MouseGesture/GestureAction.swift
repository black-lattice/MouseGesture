import AppKit

enum ActionCategory: String, CaseIterable, Identifiable {
    case system, screenshots, windows, editing, navigation, finder, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "系统与桌面"
        case .screenshots: return "截屏与录屏"
        case .windows: return "窗口与应用"
        case .editing: return "编辑与文稿"
        case .navigation: return "浏览器与标签页"
        case .finder: return "访达"
        case .custom: return "自定义功能"
        }
    }
    var hint: String {
        switch self {
        case .system: return "快捷键需在系统设置中启用并保持一致；切换桌面需要已创建多个桌面。"
        case .screenshots: return "使用 macOS 截屏功能；录屏需在截屏工具栏中选择。"
        case .windows: return "作用于手势开始位置的窗口；部分功能需要应用支持。关闭窗口直接操作该窗口关闭按钮。"
        case .editing: return "作用于手势开始位置的窗口及其中选中内容，具体行为由目标应用决定。"
        case .navigation: return "适用于支持这些快捷键的浏览器或应用；如需其他组合，请添加自定义功能。"
        case .finder: return "仅在访达窗口中绘制时执行，作用于该窗口或其中已选中的文件。"
        case .custom: return "应用内快捷键作用于手势开始位置的窗口；全局快捷键由注册它的软件处理。请确保对应软件正在运行。"
        }
    }
}

enum GestureAction: String, CaseIterable, Codable, Identifiable {
    case none, showDesktop, closeTab, closeWindow, spaceLeft, spaceRight, missionControl
    case appWindows, spotlight, finderSearch, toggleDock, emoji, previousInputSource, nextInputSource
    case lockScreen, accessibilityPanel
    case screenshotToolbar, screenshotFull, screenshotArea, screenshotFullClipboard, screenshotAreaClipboard
    case minimizeWindow, minimizeAllWindows, fullScreen, hideApp, hideOtherApps, nextWindow, previousWindow
    case appSettings, quitApp, newWindow
    case cut, copy, paste, pasteMatchingStyle, selectAll, undo, redo, find, findNext, findPrevious, openFile, save, printDocument
    case newTab, nextTab, previousTab, goBack, goForward, reloadPage, addressBar
    case newFolder, fileInfo, quickLook, parentFolder, goToFolder, downloadsFolder, desktopFolder, homeFolder, connectServer, moveToTrash

    static let available: [Self] = allCases.filter { $0 != .none }
    var id: String { rawValue }
    var title: String { definition.title }
    var category: ActionCategory { definition.category }
    var usesShortcut: Bool { definition.shortcut != nil }
    var requiresTargetWindow: Bool {
        switch self {
        case .none, .showDesktop, .spaceLeft, .spaceRight, .missionControl, .spotlight,
             .finderSearch, .toggleDock, .previousInputSource, .nextInputSource, .lockScreen,
             .accessibilityPanel, .screenshotToolbar, .screenshotFull, .screenshotArea,
             .screenshotFullClipboard, .screenshotAreaClipboard:
            return false
        default:
            // App Exposé and emoji entry still depend on the intended application/input focus.
            return true
        }
    }

    func isAvailable(in bundleID: String?) -> Bool {
        category != .finder || bundleID == "com.apple.finder"
    }

    // Default shortcuts follow Apple's macOS and Safari shortcut references.
    // Fn/Globe-only, media, power and held-key sequences require separate implementations.
    private var definition: ActionDefinition {
        switch self {
        case .none: return .init(title: "不执行操作", category: .system, shortcut: nil)
        case .showDesktop: return .key("显示桌面", .system, 103, [], "F11")
        case .missionControl: return .key("调度中心", .system, 126, [.maskControl], "↑")
        case .appWindows: return .key("显示当前应用所有窗口", .system, 125, [.maskControl], "↓")
        case .spaceLeft: return .key("切换到左侧桌面", .system, 123, [.maskControl], "←")
        case .spaceRight: return .key("切换到右侧桌面", .system, 124, [.maskControl], "→")
        case .spotlight: return .key("聚焦搜索", .system, 49, [.maskCommand], "空格")
        case .finderSearch: return .key("在访达中搜索", .system, 49, [.maskAlternate, .maskCommand], "空格")
        case .toggleDock: return .key("显示 / 隐藏程序坞", .system, 2, [.maskAlternate, .maskCommand], "D")
        case .emoji: return .key("表情与符号", .system, 49, [.maskControl, .maskCommand], "空格")
        case .previousInputSource: return .key("切换到上一个输入法", .system, 49, [.maskControl], "空格")
        case .nextInputSource: return .key("切换到下一个输入法", .system, 49, [.maskControl, .maskAlternate], "空格")
        case .lockScreen: return .key("锁定屏幕", .system, 12, [.maskControl, .maskCommand], "Q")
        case .accessibilityPanel: return .key("辅助功能快捷键面板", .system, 96, [.maskAlternate, .maskCommand], "F5")
        case .screenshotToolbar: return .key("截屏 / 录屏工具栏", .screenshots, 23, [.maskShift, .maskCommand], "5")
        case .screenshotFull: return .key("截取整个屏幕", .screenshots, 20, [.maskShift, .maskCommand], "3")
        case .screenshotArea: return .key("截取选定区域", .screenshots, 21, [.maskShift, .maskCommand], "4")
        case .screenshotFullClipboard: return .key("全屏截图到剪贴板", .screenshots, 20, [.maskControl, .maskShift, .maskCommand], "3")
        case .screenshotAreaClipboard: return .key("区域截图到剪贴板", .screenshots, 21, [.maskControl, .maskShift, .maskCommand], "4")
        case .closeTab: return .key("关闭当前标签页 / 文稿", .windows, 13, [.maskCommand], "W")
        case .closeWindow: return .init(title: "关闭当前窗口", category: .windows, shortcut: nil)
        case .minimizeWindow: return .key("最小化当前窗口", .windows, 46, [.maskCommand], "M")
        case .minimizeAllWindows: return .key("最小化当前应用所有窗口", .windows, 46, [.maskAlternate, .maskCommand], "M")
        case .fullScreen: return .key("进入 / 退出全屏", .windows, 3, [.maskControl, .maskCommand], "F")
        case .hideApp: return .key("隐藏当前应用", .windows, 4, [.maskCommand], "H")
        case .hideOtherApps: return .key("隐藏其他应用", .windows, 4, [.maskAlternate, .maskCommand], "H")
        case .nextWindow: return .key("当前应用的下一个窗口", .windows, 50, [.maskCommand], "`")
        case .previousWindow: return .key("当前应用的上一个窗口", .windows, 50, [.maskShift, .maskCommand], "`")
        case .appSettings: return .key("打开当前应用设置", .windows, 43, [.maskCommand], ",")
        case .quitApp: return .key("退出当前应用", .windows, 12, [.maskCommand], "Q")
        case .newWindow: return .key("新建窗口 / 文稿", .windows, 45, [.maskCommand], "N")
        case .cut: return .key("剪切", .editing, 7, [.maskCommand], "X")
        case .copy: return .key("复制", .editing, 8, [.maskCommand], "C")
        case .paste: return .key("粘贴", .editing, 9, [.maskCommand], "V")
        case .pasteMatchingStyle: return .key("粘贴并匹配样式", .editing, 9, [.maskAlternate, .maskShift, .maskCommand], "V")
        case .selectAll: return .key("全选", .editing, 0, [.maskCommand], "A")
        case .undo: return .key("撤销", .editing, 6, [.maskCommand], "Z")
        case .redo: return .key("重做", .editing, 6, [.maskShift, .maskCommand], "Z")
        case .find: return .key("查找", .editing, 3, [.maskCommand], "F")
        case .findNext: return .key("查找下一个", .editing, 5, [.maskCommand], "G")
        case .findPrevious: return .key("查找上一个", .editing, 5, [.maskShift, .maskCommand], "G")
        case .openFile: return .key("打开文件", .editing, 31, [.maskCommand], "O")
        case .save: return .key("保存", .editing, 1, [.maskCommand], "S")
        case .printDocument: return .key("打印", .editing, 35, [.maskCommand], "P")
        case .newTab: return .key("新建标签页", .navigation, 17, [.maskCommand], "T")
        case .nextTab: return .key("下一个标签页", .navigation, 48, [.maskControl], "Tab")
        case .previousTab: return .key("上一个标签页", .navigation, 48, [.maskControl, .maskShift], "Tab")
        case .goBack: return .key("后退", .navigation, 33, [.maskCommand], "[")
        case .goForward: return .key("前进", .navigation, 30, [.maskCommand], "]")
        case .reloadPage: return .key("刷新页面", .navigation, 15, [.maskCommand], "R")
        case .addressBar: return .key("定位地址栏", .navigation, 37, [.maskCommand], "L")
        case .newFolder: return .key("新建文件夹", .finder, 45, [.maskShift, .maskCommand], "N")
        case .fileInfo: return .key("显示文件简介", .finder, 34, [.maskCommand], "I")
        case .quickLook: return .key("快速查看文件", .finder, 16, [.maskCommand], "Y")
        case .parentFolder: return .key("打开上级文件夹", .finder, 126, [.maskCommand], "↑")
        case .goToFolder: return .key("前往文件夹", .finder, 5, [.maskShift, .maskCommand], "G")
        case .downloadsFolder: return .key("打开下载文件夹", .finder, 37, [.maskAlternate, .maskCommand], "L")
        case .desktopFolder: return .key("打开桌面文件夹", .finder, 2, [.maskShift, .maskCommand], "D")
        case .homeFolder: return .key("打开个人文件夹", .finder, 4, [.maskShift, .maskCommand], "H")
        case .connectServer: return .key("连接服务器", .finder, 40, [.maskCommand], "K")
        case .moveToTrash: return .key("移到废纸篓", .finder, 51, [.maskCommand], "⌫")
        }
    }

    fileprivate var defaultShortcut: KeyboardShortcut? { definition.shortcut }
}

private struct ActionDefinition {
    var title: String
    var category: ActionCategory
    var shortcut: KeyboardShortcut?

    static func key(_ title: String, _ category: ActionCategory, _ code: UInt16,
                    _ flags: CGEventFlags, _ key: String) -> Self {
        let symbols: [(CGEventFlags, String)] = [(.maskControl, "⌃"), (.maskAlternate, "⌥"), (.maskShift, "⇧"), (.maskCommand, "⌘")]
        let label = (symbols.filter { flags.contains($0.0) }.map { $0.1 } + [key]).joined(separator: " ")
        return .init(title: title, category: category, shortcut: .init(keyCode: code, modifiers: flags.rawValue, label: label))
    }
}

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var label: String

    static func standard(for action: GestureAction) -> Self? { action.defaultShortcut }

    static func isCancel(_ event: NSEvent) -> Bool {
        event.keyCode == 53 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    static func recorded(from event: NSEvent) -> Self? {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let functionKeys: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14",
            113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let special: [UInt16: String] = [49: "空格", 48: "Tab", 51: "⌫", 36: "Return", 53: "Esc",
                                        123: "←", 124: "→", 125: "↓", 126: "↑"]
        guard !isCancel(event), !flags.isEmpty || functionKeys[event.keyCode] != nil || (123...126).contains(event.keyCode) else {
            return nil
        }
        let modifiers: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let key = functionKeys[event.keyCode] ?? special[event.keyCode]
            ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let label = (modifiers.filter { flags.contains($0.0) }.map { $0.1 } + [key]).joined(separator: " ")
        return .init(keyCode: event.keyCode, modifiers: UInt64(flags.rawValue), label: label)
    }
}
