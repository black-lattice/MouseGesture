import Foundation
import GestureCore

struct ConfigurationFile: Codable {
    var format = "MouseGesture"
    var version = 1
    var preferences: Preferences.Saved
}

struct ConfigurationImport {
    let replacement: Preferences.Saved
    let merged: Preferences.Saved
    let conflicts: [String]
}

enum ConfigurationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        if case .invalid(let message) = self { return message }
        return nil
    }
}

extension Preferences {
    func exportConfiguration() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ConfigurationFile(preferences: snapshot))
    }

    func prepareImport(_ data: Data) throws -> ConfigurationImport {
        guard data.count <= 5_000_000 else { throw ConfigurationError.invalid("配置文件不能超过 5 MB。") }
        let file = try JSONDecoder().decode(ConfigurationFile.self, from: data)
        guard file.format == "MouseGesture", file.version == 1 else {
            throw ConfigurationError.invalid("不支持此配置格式或版本。")
        }
        let incoming = file.preferences
        try Self.validate(incoming)
        var merged = snapshot
        var conflicts: [String] = []
        let incomingGlobal = ApplicationProfile(bindings: incoming.bindings, shortcuts: incoming.shortcuts,
            customActions: incoming.customActions ?? [], mouseBindings: incoming.mouseBindings ?? [:])
        let global = Self.merge(globalProfile, incomingGlobal, name: "全局", physical: true, conflicts: &conflicts)
        merged.bindings = global.bindings
        merged.shortcuts = global.shortcuts
        merged.customActions = global.customActions
        merged.mouseBindings = global.mouseBindings
        for (id, profile) in (incoming.profiles ?? [:]).sorted(by: { $0.key < $1.key }) {
            merged.profiles?[id] = Self.merge(profiles[id] ?? ApplicationProfile(), profile, name: id, conflicts: &conflicts)
        }
        let excluded = Set(excludedApplications + incoming.excludedBundleIDs.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init))
        merged.excludedBundleIDs = excluded.sorted().joined(separator: "\n")
        // Merge retains local appearance and trigger choices; replacement adopts the file's choices.
        try Self.validate(merged)
        return ConfigurationImport(replacement: incoming, merged: merged, conflicts: conflicts)
    }

    private static func merge(_ current: ApplicationProfile, _ incoming: ApplicationProfile, name: String, physical: Bool = false,
                              conflicts: inout [String]) -> ApplicationProfile {
        var result = current
        var patterns = Set(current.bindings.map(\.pattern) + current.customActions.map(\.pattern).filter { !$0.isEmpty })
        for binding in incoming.bindings {
            guard !patterns.contains(binding.pattern), !result.bindings.contains(where: { $0.action == binding.action }) else {
                conflicts.append("\(name)：\(binding.arrows) → \(binding.action.title)")
                continue
            }
            result.bindings.append(binding)
            patterns.insert(binding.pattern)
        }
        for action in incoming.customActions {
            guard (action.pattern.isEmpty || !patterns.contains(action.pattern)),
                  !result.customActions.contains(where: { $0.id == action.id || $0.name.localizedCaseInsensitiveCompare(action.name) == .orderedSame }) else {
                conflicts.append("\(name)：自定义功能“\(action.name)”")
                continue
            }
            result.customActions.append(action)
            if !action.pattern.isEmpty { patterns.insert(action.pattern) }
        }
        for (key, value) in incoming.shortcuts {
            if result.shortcuts[key] != nil { conflicts.append("\(name)：内置快捷键 \(key)") }
            else { result.shortcuts[key] = value }
        }
        for (key, value) in incoming.mouseBindings {
            if result.mouseBindings[key] != nil || physical && result.mouseBindings.contains(where: { $0.value.buttonNumber == value.buttonNumber }) {
                conflicts.append("\(name)：鼠标按键 \(key)")
            } else { result.mouseBindings[key] = value }
        }
        // Omitted defaults are still real physical buttons: do not create duplicate mappings.
        let numbers = MouseButton.allCases.map { result.mouseBindings[$0.rawValue]?.buttonNumber ?? $0.defaultNumber }
        if physical && Set(numbers).count != numbers.count {
            result.mouseBindings = current.mouseBindings
            conflicts.append("\(name)：物理按键编号冲突，保留本机鼠标绑定")
        }
        return result
    }

    static func validate(_ value: Saved) throws {
        guard value.minimumLength.isFinite, (30...140).contains(value.minimumLength),
              (1...31).contains(value.triggerButton ?? 1),
              (value.trailWidth ?? 4).isFinite, (2...10).contains(value.trailWidth ?? 4),
              (value.profiles?.count ?? 0) <= 200 else {
            throw ConfigurationError.invalid("识别长度、触发按键、轨迹宽度或应用数量无效。")
        }
        var profiles = value.profiles ?? [:]
        guard profiles.keys.allSatisfy({ !$0.isEmpty && $0.count <= 255 && !$0.contains(where: { $0.isWhitespace }) }) else {
            throw ConfigurationError.invalid("应用标识无效。")
        }
        profiles[""] = ApplicationProfile(bindings: value.bindings, shortcuts: value.shortcuts,
            customActions: value.customActions ?? [], mouseBindings: value.mouseBindings ?? [:])
        func validPattern(_ pattern: String) -> Bool {
            let directions = pattern.compactMap { Direction(rawValue: String($0)) }
            return (1...4).contains(pattern.count) && directions.count == pattern.count
                && zip(directions, directions.dropFirst()).allSatisfy { $0 != $1 }
        }
        func validShortcut(_ shortcut: KeyboardShortcut) -> Bool {
            shortcut.keyCode <= 127 && !shortcut.label.isEmpty && shortcut.label.count <= 100
                && shortcut.modifiers & ~UInt64(0x1E0000) == 0
        }
        for (id, profile) in profiles {
            let patterns = profile.bindings.map(\.pattern) + profile.customActions.map(\.pattern).filter { !$0.isEmpty }
            let numbers = MouseButton.allCases.map { profile.mouseBindings[$0.rawValue]?.buttonNumber ?? $0.defaultNumber }
            guard patterns.count <= 1000, patterns.allSatisfy(validPattern), Set(patterns).count == patterns.count,
                  profile.bindings.allSatisfy({ $0.action != .none }), profile.customActions.count <= 1000,
                  Set(profile.customActions.map(\.id)).count == profile.customActions.count,
                  Set(profile.customActions.map { $0.name.lowercased() }).count == profile.customActions.count,
                  profile.customActions.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validShortcut($0.shortcut) }),
                  profile.shortcuts.allSatisfy({ GestureAction(rawValue: $0.key) != nil && validShortcut($0.value) }),
                  profile.mouseBindings.keys.allSatisfy({ MouseButton(rawValue: $0) != nil }),
                  numbers.allSatisfy({ (2...31).contains($0) }), (id != "" || Set(numbers).count == numbers.count),
                  profile.mouseBindings.values.allSatisfy({ $0.shortcut.map(validShortcut) ?? true }) else {
                throw ConfigurationError.invalid("配置包含无效或重复的手势、快捷键、功能或鼠标按键。")
            }
        }
    }
}
