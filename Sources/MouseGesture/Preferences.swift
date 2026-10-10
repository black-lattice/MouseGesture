import AppKit
import Combine
import GestureCore

enum GestureAction: String, CaseIterable, Codable, Identifiable {
    case none, showDesktop, closeTab, closeWindow, spaceLeft, spaceRight, missionControl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "不执行操作"
        case .showDesktop: return "显示桌面"
        case .closeTab: return "关闭当前标签页 / 文稿"
        case .closeWindow: return "关闭当前窗口"
        case .spaceLeft: return "切换到左侧桌面"
        case .spaceRight: return "切换到右侧桌面"
        case .missionControl: return "调度中心"
        }
    }
}

struct GestureBinding: Identifiable, Codable {
    var pattern: String
    var action: GestureAction
    var id: String { pattern }
    var arrows: String { pattern.compactMap { Direction(rawValue: String($0))?.arrow }.joined(separator: " ") }
    static let defaults: [Self] = [
        .init(pattern: "L", action: .spaceLeft), .init(pattern: "R", action: .spaceRight),
        .init(pattern: "D", action: .showDesktop), .init(pattern: "U", action: .missionControl),
        .init(pattern: "DR", action: .closeTab), .init(pattern: "DL", action: .closeWindow),
        .init(pattern: "UR", action: .none), .init(pattern: "UD", action: .none)
    ]
}

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt64
    var label: String

    static func standard(for action: GestureAction) -> Self {
        switch action {
        case .showDesktop: return .init(keyCode: 103, modifiers: 0, label: "F11")
        case .spaceLeft: return .init(keyCode: 123, modifiers: CGEventFlags.maskControl.rawValue, label: "⌃ ←")
        case .spaceRight: return .init(keyCode: 124, modifiers: CGEventFlags.maskControl.rawValue, label: "⌃ →")
        case .missionControl: return .init(keyCode: 126, modifiers: CGEventFlags.maskControl.rawValue, label: "⌃ ↑")
        default: return .init(keyCode: 13, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘ W")
        }
    }
}

final class Preferences: ObservableObject {
    @Published var enabled = true { didSet { save() } }
    @Published var showTrail = true { didSet { save() } }
    @Published var minimumLength: Double = 50 { didSet { save() } }
    @Published var bindings = GestureBinding.defaults { didSet { save() } }
    @Published var shortcuts: [String: KeyboardShortcut] = [:] { didSet { save() } }
    @Published var excludedBundleIDs = "" { didSet { save() } }

    private struct Saved: Codable {
        var enabled: Bool
        var showTrail: Bool
        var minimumLength: Double
        var bindings: [GestureBinding]
        var shortcuts: [String: KeyboardShortcut]
        var excludedBundleIDs: String
    }

    init() {
        guard let data = UserDefaults.standard.data(forKey: "preferences.v1"),
              let value = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        enabled = value.enabled
        showTrail = value.showTrail
        minimumLength = min(140, max(30, value.minimumLength))
        bindings = value.bindings
        shortcuts = value.shortcuts
        excludedBundleIDs = value.excludedBundleIDs
    }

    func action(for directions: [Direction]) -> GestureAction {
        let pattern = directions.map(\.rawValue).joined()
        return bindings.first { $0.pattern == pattern }?.action ?? .none
    }

    func shortcut(for action: GestureAction) -> KeyboardShortcut {
        shortcuts[action.rawValue] ?? .standard(for: action)
    }

    func excludes(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .contains { String($0) == bundleID }
    }

    func restoreDefaults() {
        bindings = GestureBinding.defaults
        shortcuts = [:]
        minimumLength = 50
    }

    private func save() {
        let value = Saved(enabled: enabled, showTrail: showTrail, minimumLength: minimumLength,
                          bindings: bindings, shortcuts: shortcuts, excludedBundleIDs: excludedBundleIDs)
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: "preferences.v1") }
    }
}
