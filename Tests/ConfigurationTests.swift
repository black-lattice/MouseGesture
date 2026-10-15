private let configurationSuite = "MouseGesture.ConfigurationTests.\(UUID().uuidString)"
private let configurationDefaults = UserDefaults(suiteName: configurationSuite)!
defer { configurationDefaults.removePersistentDomain(forName: configurationSuite) }
private let configuration = Preferences(defaults: configurationDefaults)
private var configurationChecks = 0
private func checkConfiguration(_ value: @autoclosure () -> Bool, _ message: String) {
    configurationChecks += 1
    if !value() { fatalError(message) }
}
let configuredCopy = KeyboardShortcut.standard(for: .copy)!
let configuredPaste = KeyboardShortcut.standard(for: .paste)!
configuration.bind([.left], to: .goBack)
configuration.bind([.up], to: .showDesktop)
configuration.setMouseShortcut(configuredCopy, for: .back)
configuration.editingBundleID = "test.editor"
checkConfiguration(configuration.bind([.left], to: .undo), "应用手势允许覆盖全局相同轨迹")
checkConfiguration(!configuration.bind([.left], to: .redo), "同一应用内部拒绝手势冲突")
configuration.setMouseShortcut(configuredPaste, for: .back)
checkConfiguration(configuration.action(for: [.left], bundleID: "test.editor") == .undo, "应用手势优先")
checkConfiguration(configuration.action(for: [.left], bundleID: "test.other") == .goBack, "其他应用仍使用全局手势")
checkConfiguration(configuration.action(for: [.up], bundleID: "test.editor") == .showDesktop, "未覆盖的手势继承全局")
checkConfiguration(configuration.mouseBinding(for: .back, bundleID: "test.editor").shortcut == configuredPaste, "侧键按应用覆盖")
checkConfiguration(configuration.mouseBinding(for: .back, bundleID: "test.other").shortcut == configuredCopy, "其他应用侧键不受编辑范围影响")
configuration.setMouseButtonNumber(8, for: .back)
checkConfiguration(configuration.mouseBinding(for: .back, bundleID: "test.editor").buttonNumber == 8, "应用配置沿用全局物理编号")
checkConfiguration(configuration.globalProfile.mouseBindings["back"]?.shortcut == configuredCopy, "专属范围识别物理按键不覆盖全局快捷键")
configuration.setMouseShortcut(nil, for: .back)
checkConfiguration(configuration.mouseBinding(for: .back, bundleID: "test.editor").shortcut == nil, "应用内可显式恢复原生鼠标行为")
configuration.mouseBindings.removeValue(forKey: "back")
checkConfiguration(configuration.mouseBinding(for: .back, bundleID: "test.editor").shortcut == configuredCopy, "移除覆盖恢复全局快捷键")
var configuredDraft = CustomActionDraft()
configuredDraft.name = "专属复制"
configuredDraft.shortcut = configuredCopy
configuredDraft.directions = [.up]
checkConfiguration(configuration.saveCustomAction(configuredDraft) == nil, "自定义功能可覆盖全局内置手势")
checkConfiguration(configuration.customAction(for: [.up], bundleID: "test.editor")?.name == "专属复制"
    && configuration.action(for: [.up], bundleID: "test.editor") == .none, "覆盖后不会同时触发全局内置操作")
configuration.clearCustomGesture(configuredDraft.id)
checkConfiguration(configuration.action(for: [.up], bundleID: "test.editor") == .showDesktop, "清除自定义覆盖恢复全局")
configuration.clearGesture(for: .undo)
checkConfiguration(configuration.action(for: [.left], bundleID: "test.editor") == .goBack, "清除内置覆盖恢复全局")
configuration.bind([.right], to: .redo)
configuration.triggerButton = 8
configuration.trailColor = .orange
configuration.trailWidth = 8
configuration.showHint = false
configuration.setExcluded("test.game", excluded: true)
configuration.setExcluded("test.game", excluded: true)
checkConfiguration(configuration.excludedApplications == ["test.game"], "可视化排除列表去重")
let configurationReload = Preferences(defaults: configurationDefaults)
checkConfiguration(configurationReload.editingBundleID.isEmpty, "重启回到全局编辑范围")
checkConfiguration(configurationReload.action(for: [.right], bundleID: "test.editor") == .redo, "应用专属配置持久化")
checkConfiguration(configurationReload.action(for: [.left], bundleID: nil) == .goBack, "编辑专属配置不丢失全局持久化数据")
checkConfiguration(configurationReload.triggerButton == 8 && configurationReload.trailWidth == 8
    && configurationReload.trailColor == .orange && !configurationReload.showHint, "触发键和外观持久化")
let configurationData = try configuration.exportConfiguration()
let importedConfiguration = try configurationReload.prepareImport(configurationData)
checkConfiguration(!importedConfiguration.conflicts.isEmpty, "导入预览列出重复绑定冲突")
checkConfiguration(importedConfiguration.merged.bindings.count == configurationReload.globalProfile.bindings.count, "合并跳过重复手势")
configurationReload.apply(importedConfiguration.replacement)
checkConfiguration(configurationReload.action(for: [.right], bundleID: "test.editor") == .redo, "覆盖导入恢复专属手势")
checkConfiguration(configurationReload.excludes("test.game") && configurationReload.triggerButton == 8, "覆盖导入恢复排除列表和触发键")
var invalidConfiguration = importedConfiguration.replacement
invalidConfiguration.bindings.append(invalidConfiguration.bindings[0])
do {
    _ = try configurationReload.prepareImport(JSONEncoder().encode(ConfigurationFile(preferences: invalidConfiguration)))
    fatalError("重复手势导入应被拒绝")
} catch { configurationChecks += 1 }
invalidConfiguration = importedConfiguration.replacement
invalidConfiguration.minimumLength = 0
do {
    try Preferences.validate(invalidConfiguration)
    fatalError("非法阈值应被拒绝")
} catch { configurationChecks += 1 }
var futureConfiguration = ConfigurationFile(preferences: importedConfiguration.replacement)
futureConfiguration.version = 999
do {
    _ = try configurationReload.prepareImport(JSONEncoder().encode(futureConfiguration))
    fatalError("未知格式版本应被拒绝")
} catch { configurationChecks += 1 }
checkConfiguration(configurationReload.action(for: [.right], bundleID: "test.editor") == .redo, "非法导入不改变已有配置")
configurationReload.editingBundleID = "test.editor"
configurationReload.restoreDefaults()
checkConfiguration(configurationReload.action(for: [.left], bundleID: nil) == .goBack, "重置专属配置不清除全局手势")
// A per-app shortcut may have been saved before a global physical button swap.
configurationReload.editingBundleID = "test.editor"
configurationReload.setMouseShortcut(configuredPaste, for: .forward)
configurationReload.setMouseButtonNumber(3, for: .forward)
let remappedData = try configurationReload.exportConfiguration()
let remappedImport = try configurationReload.prepareImport(remappedData)
checkConfiguration(remappedImport.replacement.profiles?["test.editor"]?.mouseBindings["forward"]?.shortcut == configuredPaste,
                   "全局交换物理编号后，旧应用快捷键仍能导出并导入")
configurationReload.editingBundleID = ""
checkConfiguration(configurationReload.mouseBinding(for: .forward, bundleID: "test.editor").buttonNumber == 3,
                   "应用侧键始终使用最新全局物理编号")
print("应用配置、导入导出与外观持久化测试通过：\(configurationChecks) 项")
