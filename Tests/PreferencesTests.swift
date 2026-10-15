// Runs through scripts/check.sh with an isolated UserDefaults suite.
let suite = "MouseGesture.Tests.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
var testCount = 0
var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    testCount += 1
    if !condition() { failures.append(name) }
}

let preferences = Preferences(defaults: defaults)
expect(preferences.bindings.isEmpty, "新用户需要自行录制，没有预设手势")
expect(GestureAction.available.count == 65 && !GestureAction.available.contains(.none), "列出六类共六十五项功能，不包括空操作")
expect(preferences.bind([.right, .down, .left], to: .showDesktop), "支持原八种预设以外的手势")
expect(preferences.action(for: [.right, .down, .left]) == .showDesktop, "录制的手势可以解析到操作")
expect(Preferences(defaults: defaults).action(for: [.right, .down, .left]) == .showDesktop, "录制后重载仍保留绑定")
expect(!preferences.bind([.right, .down, .left], to: .closeWindow), "重复手势拒绝绑定其他功能")
expect(preferences.action(for: [.right, .down, .left]) == .showDesktop, "冲突不会覆盖原操作")
expect(preferences.bind([.up, .left], to: .showDesktop), "可以重新录制同一功能")
expect(preferences.action(for: [.right, .down, .left]) == .none, "重录后原手势失效")
expect(!preferences.bind([], to: .closeTab), "空手势不能保存")
expect(!preferences.bind([.up, .down, .left, .right, .up], to: .closeTab), "超过四段不能保存")
expect(!preferences.bind([.down], to: .none), "不能为无操作录制手势")
preferences.clearGesture(for: .showDesktop)
expect(Preferences(defaults: defaults).action(for: [.up, .left]) == .none, "清除后不会执行，且重载保持清除")

expect(preferences.shortcut(for: .closeWindow) == nil && preferences.shortcut(for: .none) == nil,
       "非快捷键操作不伪装为 Command-W")
expect(GestureAction.available.filter(\.usesShortcut).allSatisfy { preferences.shortcut(for: $0) != nil },
       "每个快捷键功能都有可发送的默认键位")
expect(GestureAction.available.filter { $0.category == .finder }.allSatisfy {
    $0.isAvailable(in: "com.apple.finder") && !$0.isAvailable(in: "com.apple.TextEdit") && !$0.isAvailable(in: nil)
}, "访达操作不会在文本编辑器或未知应用中执行")
expect(GestureAction.copy.isAvailable(in: "com.apple.TextEdit") && GestureAction.spotlight.isAvailable(in: nil),
       "通用编辑和系统功能不会受到访达限制")
let screenFile = preferences.shortcut(for: .screenshotFull)!
let screenClipboard = preferences.shortcut(for: .screenshotFullClipboard)!
expect(screenFile.keyCode == screenClipboard.keyCode
       && screenClipboard.modifiers == screenFile.modifiers | CGEventFlags.maskControl.rawValue,
       "复制截图比保存截图多 Control 修饰键")
let custom = KeyboardShortcut(keyCode: 18, modifiers: CGEventFlags.maskControl.rawValue, label: "⌃ 1")
preferences.shortcuts[GestureAction.spotlight.rawValue] = custom
expect(Preferences(defaults: defaults).shortcut(for: .spotlight) == custom, "新增系统功能的自定义快捷键可持久化")

// Give every catalog entry a distinct, recognizable pattern and reload the whole configuration.
var patterns: [[Direction]] = [[]]
for _ in 0..<4 {
    patterns = patterns.flatMap { prefix in Direction.allCases.filter { $0 != prefix.last }.map { prefix + [$0] } }
}
for (action, pattern) in zip(GestureAction.available, patterns) {
    expect(preferences.bind(pattern, to: action), "为\(action.title)录制独立手势")
}
let catalogReload = Preferences(defaults: defaults)
expect(zip(GestureAction.available, patterns).allSatisfy { catalogReload.action(for: $0.1) == $0.0 },
       "重载后全部六十五项功能仍可通过对应手势找到")

// Same preferences.v1 schema used by the previous release, including multiple gestures per action.
let legacy: [String: Any] = [
    "enabled": false, "showTrail": false, "minimumLength": 70,
    "bindings": [["pattern": "D", "action": "showDesktop"], ["pattern": "UD", "action": "showDesktop"],
                 ["pattern": "UR", "action": "none"], ["pattern": "DL", "action": "closeWindow"]],
    "shortcuts": ["showDesktop": ["keyCode": 103, "modifiers": 0, "label": "F11"]],
    "excludedBundleIDs": "com.apple.Safari"
]
defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: "preferences.v1")
let restored = Preferences(defaults: defaults)
expect(restored.gestures(for: .showDesktop) == "↓ / ↑ ↓", "旧配置的多个手势均可展示")
expect(restored.action(for: [.down, .left]) == .closeWindow, "旧绑定仍然有效")
expect(!restored.enabled && !restored.showTrail && restored.minimumLength == 70
       && restored.excludes("com.apple.Safari") && restored.shortcut(for: .showDesktop)?.label == "F11", "保留旧配置的其他设置")
expect(restored.bind([.up, .right], to: .showDesktop), "旧版未绑定预设不会占用手势")
expect(restored.action(for: [.down]) == .none && restored.action(for: [.up, .down]) == .none,
       "重录替换该功能的全部旧手势")
expect(restored.action(for: [.down, .left]) == .closeWindow, "重录不影响其他功能")
restored.restoreDefaults()
let reset = Preferences(defaults: defaults)
expect(reset.bindings.isEmpty && reset.shortcuts.isEmpty && reset.minimumLength == 50, "重置清除手势并恢复快捷键和长度")
expect(!reset.enabled && !reset.showTrail && reset.excludes("com.apple.Safari"), "重置不影响开关及排除应用")

if failures.isEmpty { print("手势绑定与配置测试通过：\(testCount) 项") }
else { failures.forEach { print("失败：\($0)") }; exit(1) }
