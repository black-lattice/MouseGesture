// This harness runs as separate optimized processes, with isolated preference domains.
let suite = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
let legacyDefaults = UserDefaults(suiteName: suite + ".legacy")!
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("失败：\(message)"); exit(1) }
}
switch mode {
case "write":
    let preferences = Preferences(defaults: legacyDefaults)
    var draft = CustomActionDraft()
    draft.name = "跨进程截图"
    draft.shortcut = .init(keyCode: 7, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue, label: "⇧ ⌘ X")
    draft.directions = [.down, .left]
    require(preferences.saveCustomAction(draft) == nil, "保存完整自定义功能")
    for button in MouseButton.allCases { preferences.setMouseShortcut(draft.shortcut, for: button) }
    require(preferences.setMouseButtonNumber(8, for: .forward), "保存实际侧键编号")
case "migrate", "read":
    let preferences = Preferences(defaults: defaults, legacyDefaults: legacyDefaults)
    let directions = GestureRecognizer.recognize([.init(x: 100, y: 100), .init(x: 100, y: 200), .init(x: 0, y: 200)])!
    guard let action = preferences.customAction(for: directions) else { fatalError("重启后识别手势找不到自定义功能") }
    require(action.name == "跨进程截图" && action.shortcut.keyCode == 7
            && action.shortcut.modifiers == CGEventFlags.maskCommand.union(.maskShift).rawValue,
            "独立进程读取、匹配手势与快捷键")
    require(MouseButton.allCases.allSatisfy { preferences.mouseBinding(for: $0).shortcut == action.shortcut }
            && preferences.mouseBinding(for: .forward).buttonNumber == 8, "独立进程保留三种鼠标绑定及识别编号")
case "edit":
    let preferences = Preferences(defaults: defaults, legacyDefaults: legacyDefaults)
    var draft = CustomActionDraft(action: preferences.customActions[0])
    draft.name = "更新后的功能"
    draft.directions = [.right, .down]
    require(preferences.saveCustomAction(draft) == nil, "编辑保存")
    preferences.setMouseShortcut(nil, for: .middle)
    preferences.setMouseButtonNumber(4, for: .back)
case "readEdited":
    let preferences = Preferences(defaults: defaults, legacyDefaults: legacyDefaults)
    require(preferences.customAction(for: [.right, .down])?.name == "更新后的功能"
            && preferences.customAction(for: [.down, .left]) == nil, "再次重启读取编辑后的功能")
    require(preferences.mouseBinding(for: .middle).shortcut == nil
            && preferences.mouseBinding(for: .back).buttonNumber == 4, "独立进程保留鼠标绑定清除与重识别")
case "delete":
    let preferences = Preferences(defaults: defaults, legacyDefaults: legacyDefaults)
    preferences.deleteCustomAction(preferences.customActions[0].id)
case "readDeleted":
    require(Preferences(defaults: defaults, legacyDefaults: legacyDefaults).customActions.isEmpty,
            "删除后重启不从旧配置复活")
case "cleanup":
    defaults.removePersistentDomain(forName: suite)
    legacyDefaults.removePersistentDomain(forName: suite + ".legacy")
default: fatalError("未知测试阶段")
}
