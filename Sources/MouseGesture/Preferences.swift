import AppKit
import Combine
import GestureCore

struct GestureBinding: Identifiable, Codable {
    var pattern: String
    var action: GestureAction
    var id: String { pattern }
    var arrows: String { pattern.compactMap { Direction(rawValue: String($0))?.arrow }.joined(separator: " ") }
}

final class Preferences: ObservableObject {
    @Published var enabled = true { didSet { save() } }
    @Published var showTrail = true { didSet { save() } }
    @Published var minimumLength: Double = 50 { didSet { save() } }
    @Published var bindings: [GestureBinding] = [] { didSet { save() } }
    @Published var shortcuts: [String: KeyboardShortcut] = [:] { didSet { save() } }
    @Published var excludedBundleIDs = "" { didSet { save() } }
    @Published private(set) var customActions: [CustomAction] = [] { didSet { save() } }
    private let defaults: UserDefaults

    private struct Saved: Codable {
        var enabled: Bool
        var showTrail: Bool
        var minimumLength: Double
        var bindings: [GestureBinding]
        var shortcuts: [String: KeyboardShortcut]
        var excludedBundleIDs: String
        var customActions: [CustomAction]?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: "preferences.v1"),
              let value = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        enabled = value.enabled
        showTrail = value.showTrail
        minimumLength = min(140, max(30, value.minimumLength))
        bindings = value.bindings
        shortcuts = value.shortcuts
        excludedBundleIDs = value.excludedBundleIDs
        customActions = value.customActions ?? []
    }

    func gestures(for action: GestureAction) -> String {
        bindings.filter { $0.action == action }.map(\.arrows).joined(separator: " / ")
    }

    func conflict(for directions: [Direction], action: GestureAction? = nil, customID: UUID? = nil) -> String? {
        let pattern = directions.map(\.rawValue).joined()
        if let binding = bindings.first(where: { $0.pattern == pattern && $0.action != action && $0.action != .none }) {
            return binding.action.title
        }
        return customActions.first { $0.pattern == pattern && $0.id != customID }?.name
    }

    @discardableResult
    func bind(_ directions: [Direction], to action: GestureAction) -> Bool {
        guard action != .none, !directions.isEmpty, directions.count <= 4,
              conflict(for: directions, action: action) == nil else { return false }
        let pattern = directions.map(\.rawValue).joined()
        bindings = bindings.filter { $0.action != action && $0.pattern != pattern }
            + [GestureBinding(pattern: pattern, action: action)]
        return true
    }

    func clearGesture(for action: GestureAction) {
        bindings.removeAll { $0.action == action }
    }

    func action(for directions: [Direction]) -> GestureAction {
        let pattern = directions.map(\.rawValue).joined()
        return bindings.first { $0.pattern == pattern }?.action ?? .none
    }

    func customAction(for directions: [Direction]) -> CustomAction? {
        guard !directions.isEmpty else { return nil }
        let pattern = directions.map(\.rawValue).joined()
        return customActions.first { $0.pattern == pattern }
    }

    func title(for directions: [Direction]) -> String {
        customAction(for: directions)?.name ?? action(for: directions).title
    }

    func validationError(for draft: CustomActionDraft) -> String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "请填写功能名称。" }
        guard !customActions.contains(where: { $0.id != draft.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) else {
            return "已有同名的自定义功能，请使用其他名称。"
        }
        guard draft.shortcut != nil else { return "请先录入软件的快捷键。" }
        guard !draft.directions.isEmpty, draft.directions.count <= 4,
              zip(draft.directions, draft.directions.dropFirst()).allSatisfy({ $0.0 != $0.1 }) else {
            return "请录制有效的鼠标手势。"
        }
        if let name = conflict(for: draft.directions, customID: draft.id) {
            return "此手势已用于“\(name)”，请重新绘制或先清除原绑定。"
        }
        return nil
    }

    @discardableResult
    func saveCustomAction(_ draft: CustomActionDraft) -> String? {
        if let error = validationError(for: draft) { return error }
        guard let shortcut = draft.shortcut else { return "请先录入软件的快捷键。" }
        let action = CustomAction(id: draft.id, name: draft.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                  shortcut: shortcut, pattern: draft.directions.map(\.rawValue).joined())
        var updated = customActions
        if let index = updated.firstIndex(where: { $0.id == draft.id }) { updated[index] = action }
        else { updated.append(action) }
        customActions = updated
        return nil
    }

    func deleteCustomAction(_ id: UUID) { customActions.removeAll { $0.id == id } }

    func clearCustomGesture(_ id: UUID) {
        guard let index = customActions.firstIndex(where: { $0.id == id }) else { return }
        customActions[index].pattern = ""
    }

    func shortcut(for action: GestureAction) -> KeyboardShortcut? {
        shortcuts[action.rawValue] ?? .standard(for: action)
    }

    func excludes(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .contains { String($0) == bundleID }
    }

    func restoreDefaults() {
        bindings = []
        shortcuts = [:]
        minimumLength = 50
        customActions = customActions.map { var action = $0; action.pattern = ""; return action }
    }

    private func save() {
        let value = Saved(enabled: enabled, showTrail: showTrail, minimumLength: minimumLength,
                          bindings: bindings, shortcuts: shortcuts, excludedBundleIDs: excludedBundleIDs,
                          customActions: customActions)
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "preferences.v1") }
    }
}
