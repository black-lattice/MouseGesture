private var mousePreferenceChecks = 0
private func checkMousePreference(_ condition: @autoclosure () -> Bool, _ message: String) {
    mousePreferenceChecks += 1
    if !condition() { fatalError(message) }
}
private let mousePreferenceSuite = "MouseGesture.MousePreferences.\(UUID().uuidString)"
private let mousePreferenceDefaults = UserDefaults(suiteName: mousePreferenceSuite)!
defer { mousePreferenceDefaults.removePersistentDomain(forName: mousePreferenceSuite) }
private let mousePreferences = Preferences(defaults: mousePreferenceDefaults)
checkMousePreference(MouseButton.allCases.allSatisfy { mousePreferences.mouseBinding(for: $0).shortcut == nil },
                     "新配置保留所有鼠标按键原功能")
private let mouseShortcut = KeyboardShortcut(keyCode: 8, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘ C")
for button in MouseButton.allCases {
    mousePreferences.setMouseShortcut(mouseShortcut, for: button)
    checkMousePreference(Preferences(defaults: mousePreferenceDefaults).mouseBinding(for: button).shortcut == mouseShortcut,
                         "三种鼠标快捷键均可持久化")
}
checkMousePreference(mousePreferences.setMouseButtonNumber(4, for: .back), "支持重新识别侧键")
checkMousePreference(mousePreferences.mouseBinding(for: .back).buttonNumber == 4
                     && mousePreferences.mouseBinding(for: .forward).buttonNumber == 3,
                     "反向侧键编号互换，不生成冲突")
checkMousePreference(mousePreferences.mouseBinding(for: .forward).shortcut == mouseShortcut, "互换按键保留各功能快捷键")
checkMousePreference(mousePreferences.setMouseButtonNumber(8, for: .forward), "支持非标准侧键编号")
checkMousePreference(Preferences(defaults: mousePreferenceDefaults).mouseBinding(for: .forward).buttonNumber == 8,
                     "识别的物理按键重启后保留")
for number: Int64 in [-1, 0, 1, 32] {
    checkMousePreference(!mousePreferences.setMouseButtonNumber(number, for: .middle), "拒绝左右键及无效编号")
}
mousePreferences.setMouseShortcut(nil, for: .forward)
checkMousePreference(Preferences(defaults: mousePreferenceDefaults).mouseBinding(for: .forward)
                     == MouseButtonBinding(buttonNumber: 8), "清除快捷键后仍记住物理按键")
mousePreferences.restoreDefaults()
let resetMousePreferences = Preferences(defaults: mousePreferenceDefaults)
checkMousePreference(resetMousePreferences.mouseBindings.isEmpty
                     && MouseButton.allCases.allSatisfy { resetMousePreferences.mouseBinding(for: $0).shortcut == nil },
                     "全局重置清除鼠标绑定")

// Omit the new optional field, exactly as older saved configurations do.
mousePreferences.setMouseShortcut(mouseShortcut, for: .middle)
var oldMouseData = try JSONSerialization.jsonObject(with: mousePreferenceDefaults.data(forKey: "preferences.v1")!) as! [String: Any]
oldMouseData.removeValue(forKey: "mouseBindings")
oldMouseData["minimumLength"] = 100
mousePreferenceDefaults.set(try JSONSerialization.data(withJSONObject: oldMouseData), forKey: "preferences.v1")
let legacyMousePreferences = Preferences(defaults: mousePreferenceDefaults)
checkMousePreference(legacyMousePreferences.mouseBindings.isEmpty && legacyMousePreferences.minimumLength == 100,
                     "旧版配置正常读取且不自动接管鼠标按键")
print("鼠标按键配置测试通过：\(mousePreferenceChecks) 项")
