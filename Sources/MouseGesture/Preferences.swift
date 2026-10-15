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
    static let domain = "com.blacklattice.MouseGesture"
    @Published var enabled = true { didSet { save() } }
    @Published var showTrail = true { didSet { save() } }
    @Published var minimumLength: Double = 50 { didSet { save() } }
    @Published var globalProfile = ApplicationProfile() { didSet { save() } }
    @Published var profiles: [String: ApplicationProfile] = [:] { didSet { save() } }
    @Published var editingBundleID = ""
    @Published var triggerButton: Int64 = 1 { didSet { save() } }
    @Published var showHint = true { didSet { save() } }
    @Published var trailColor = TrailColor.teal { didSet { save() } }
    @Published var trailWidth: Double = 4 { didSet { save() } }
    var bindings: [GestureBinding] {
        get { editingProfile.bindings }
        set { editingProfile.bindings = newValue }
    }
    var shortcuts: [String: KeyboardShortcut] {
        get { editingProfile.shortcuts }
        set { editingProfile.shortcuts = newValue }
    }
    var mouseBindings: [String: MouseButtonBinding] {
        get { editingProfile.mouseBindings }
        set { editingProfile.mouseBindings = newValue }
    }
    @Published var excludedBundleIDs = "" { didSet { save() } }
    var customActions: [CustomAction] {
        get { editingProfile.customActions }
        set { editingProfile.customActions = newValue }
    }
    var editingProfile: ApplicationProfile {
        get { editingBundleID.isEmpty ? globalProfile : profiles[editingBundleID] ?? ApplicationProfile() }
        set {
            if editingBundleID.isEmpty { globalProfile = newValue }
            else { profiles[editingBundleID] = newValue }
        }
    }
    private let defaults: UserDefaults
    private var isLoading = true

    struct Saved: Codable {
        var enabled: Bool
        var showTrail: Bool
        var minimumLength: Double
        var bindings: [GestureBinding]
        var shortcuts: [String: KeyboardShortcut]
        var excludedBundleIDs: String
        var customActions: [CustomAction]?
        var mouseBindings: [String: MouseButtonBinding]?
        var profiles: [String: ApplicationProfile]?
        var triggerButton: Int64?
        var showHint: Bool?
        var trailColor: TrailColor?
        var trailWidth: Double?
    }

    convenience init(domain: String = Preferences.domain, legacyDomain: String? = "MouseGesture") {
        // The installed app's domain is its bundle ID: suiteName rejects that ID.
        // Package executables use a suite to reach the same settings instead.
        self.init(defaults: Self.defaults(for: domain),
                  legacyDefaults: legacyDomain.map { Self.defaults(for: $0) })
    }

    private static func defaults(for domain: String) -> UserDefaults {
        if Bundle.main.bundleIdentifier == domain { return .standard }
        return UserDefaults(suiteName: domain) ?? .standard
    }

    init(defaults: UserDefaults, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        let needsMigration = legacyDefaults != nil && !defaults.bool(forKey: "preferences.legacyMigrated.v1")
        let legacy = needsMigration ? legacyDefaults.flatMap { Self.read(from: $0) } : nil
        if let value = Self.read(from: defaults) ?? legacy {
            enabled = value.enabled
            showTrail = value.showTrail
            minimumLength = min(140, max(30, value.minimumLength))
            bindings = value.bindings
            shortcuts = value.shortcuts
            excludedBundleIDs = value.excludedBundleIDs
            customActions = value.customActions ?? []
            mouseBindings = value.mouseBindings ?? [:]
            profiles = value.profiles ?? [:]
            triggerButton = (1...31).contains(value.triggerButton ?? 1) ? value.triggerButton ?? 1 : 1
            showHint = value.showHint ?? value.showTrail
            trailColor = value.trailColor ?? .teal
            trailWidth = min(10, max(2, value.trailWidth ?? 4))
        }
        // Preserve installed settings; recover missing custom actions only once.
        for var action in legacy?.customActions ?? [] {
            guard !customActions.contains(where: {
                $0.id == action.id || $0.name.localizedCaseInsensitiveCompare(action.name) == .orderedSame
            }) else { continue }
            if conflict(for: action.directions) != nil { action.pattern = "" }
            customActions.append(action)
        }
        isLoading = false
        if needsMigration {
            save()
            defaults.set(true, forKey: "preferences.legacyMigrated.v1")
        }
    }

    private static func read(from defaults: UserDefaults) -> Saved? {
        guard let data = defaults.data(forKey: "preferences.v1") else { return nil }
        return try? JSONDecoder().decode(Saved.self, from: data)
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
        mouseBindings = [:]
        if editingBundleID.isEmpty { minimumLength = 50 }
        customActions = customActions.map { var action = $0; action.pattern = ""; return action }
    }

    var snapshot: Saved {
        Saved(enabled: enabled, showTrail: showTrail, minimumLength: minimumLength,
              bindings: globalProfile.bindings, shortcuts: globalProfile.shortcuts, excludedBundleIDs: excludedBundleIDs,
              customActions: globalProfile.customActions, mouseBindings: globalProfile.mouseBindings,
              profiles: profiles, triggerButton: triggerButton, showHint: showHint, trailColor: trailColor, trailWidth: trailWidth)
    }

    func apply(_ value: Saved) {
        isLoading = true
        globalProfile = ApplicationProfile(bindings: value.bindings, shortcuts: value.shortcuts,
                                           customActions: value.customActions ?? [], mouseBindings: value.mouseBindings ?? [:])
        profiles = value.profiles ?? [:]
        excludedBundleIDs = value.excludedBundleIDs
        showTrail = value.showTrail
        showHint = value.showHint ?? value.showTrail
        minimumLength = value.minimumLength
        triggerButton = value.triggerButton ?? 1
        trailColor = value.trailColor ?? .teal
        trailWidth = value.trailWidth ?? 4
        editingBundleID = ""
        isLoading = false
        save()
    }

    private func save() {
        guard !isLoading else { return }
        if let data = try? JSONEncoder().encode(snapshot) { defaults.set(data, forKey: "preferences.v1") }
    }
}
