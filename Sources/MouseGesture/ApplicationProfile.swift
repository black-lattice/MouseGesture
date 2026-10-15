import AppKit
import GestureCore

struct ApplicationProfile: Codable {
    var bindings: [GestureBinding] = []
    var shortcuts: [String: KeyboardShortcut] = [:]
    var customActions: [CustomAction] = []
    var mouseBindings: [String: MouseButtonBinding] = [:]
}

enum TrailColor: String, Codable, CaseIterable, Identifiable {
    case teal, blue, orange, pink, white
    var id: String { rawValue }
    var title: String {
        switch self {
        case .teal: return "青色"
        case .blue: return "蓝色"
        case .orange: return "橙色"
        case .pink: return "粉色"
        case .white: return "白色"
        }
    }
    var color: NSColor {
        switch self {
        case .teal: return .systemTeal
        case .blue: return .systemBlue
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .white: return .white
        }
    }
}

extension Preferences {
    func resolvedProfile(for bundleID: String?) -> ApplicationProfile {
        guard let bundleID, let local = profiles[bundleID] else { return globalProfile }
        let overridden = Set(local.bindings.map(\.pattern) + local.customActions.map(\.pattern).filter { !$0.isEmpty })
        return ApplicationProfile(
            bindings: local.bindings + globalProfile.bindings.filter { !overridden.contains($0.pattern) },
            shortcuts: globalProfile.shortcuts.merging(local.shortcuts) { _, new in new },
            customActions: local.customActions.filter { !$0.pattern.isEmpty }
                + globalProfile.customActions.filter { !overridden.contains($0.pattern) },
            mouseBindings: globalProfile.mouseBindings.merging(local.mouseBindings) { _, new in new })
    }

    func action(for directions: [Direction], bundleID: String?) -> GestureAction {
        let pattern = directions.map(\.rawValue).joined()
        return resolvedProfile(for: bundleID).bindings.first { $0.pattern == pattern }?.action ?? .none
    }

    func customAction(for directions: [Direction], bundleID: String?) -> CustomAction? {
        guard !directions.isEmpty else { return nil }
        let pattern = directions.map(\.rawValue).joined()
        return resolvedProfile(for: bundleID).customActions.first { $0.pattern == pattern }
    }

    func title(for directions: [Direction], bundleID: String?) -> String {
        customAction(for: directions, bundleID: bundleID)?.name ?? action(for: directions, bundleID: bundleID).title
    }

    func shortcut(for action: GestureAction, bundleID: String?) -> KeyboardShortcut? {
        resolvedProfile(for: bundleID).shortcuts[action.rawValue] ?? .standard(for: action)
    }

    func mouseBinding(for button: MouseButton, bundleID: String?) -> MouseButtonBinding {
        var binding = bundleID.flatMap { profiles[$0]?.mouseBindings[button.rawValue] }
            ?? globalProfile.mouseBindings[button.rawValue] ?? MouseButtonBinding(buttonNumber: button.defaultNumber)
        binding.buttonNumber = globalProfile.mouseBindings[button.rawValue]?.buttonNumber ?? button.defaultNumber
        return binding
    }

    var excludedApplications: [String] {
        Array(Set(excludedBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))).sorted()
    }

    func setExcluded(_ bundleID: String, excluded: Bool) {
        var values = Set(excludedApplications)
        if excluded { values.insert(bundleID) } else { values.remove(bundleID) }
        excludedBundleIDs = values.sorted().joined(separator: "\n")
    }

    var triggerTitle: String {
        if triggerButton == 1 { return "右键" }
        if triggerButton == 2 { return "中键" }
        return "鼠标按键 \(triggerButton)"
    }
}
