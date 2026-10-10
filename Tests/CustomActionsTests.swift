// Appended to the preferences test harness; all writes use an isolated domain.
let customSuite = "MouseGesture.CustomTests.\(UUID().uuidString)"
let customDefaults = UserDefaults(suiteName: customSuite)!
defer { customDefaults.removePersistentDomain(forName: customSuite) }
let customPreferences = Preferences(defaults: customDefaults)
var customCount = 0
var customFailures: [String] = []
func checkCustom(_ condition: @autoclosure () -> Bool, _ name: String) {
    customCount += 1
    if !condition() { customFailures.append(name) }
}

checkCustom(restored.customActions.isEmpty, "缺少自定义字段的旧配置正常读取")
var draft = CustomActionDraft()
checkCustom(customPreferences.saveCustomAction(draft) != nil && customPreferences.customActions.isEmpty, "空草稿不能保存")
draft.name = "  音乐播放 / 暂停  "
checkCustom(customPreferences.saveCustomAction(draft) != nil, "没有快捷键不能保存")
draft.shortcut = .init(keyCode: 35, modifiers: CGEventFlags.maskCommand.union(.maskAlternate).rawValue, label: "⌥ ⌘ P")
checkCustom(customPreferences.saveCustomAction(draft) != nil, "没有手势不能保存")
draft.directions = [.right, .down]
checkCustom(customPreferences.customActions.isEmpty && customPreferences.customAction(for: draft.directions) == nil,
            "填写完整但尚未保存的草稿不会生效")
checkCustom(customPreferences.saveCustomAction(draft) == nil, "完整草稿一次保存成功")
let saved = customPreferences.customActions[0]
checkCustom(saved.name == "音乐播放 / 暂停" && saved.id == draft.id && saved.shortcut == draft.shortcut, "名称去空格，ID 和快捷键保留")
checkCustom(customPreferences.customAction(for: [.right, .down]) == saved, "保存后手势立即解析到自定义功能")
checkCustom(customPreferences.title(for: [.right, .down]) == saved.name, "轨迹预览使用自定义名称")
checkCustom(Preferences(defaults: customDefaults).customActions == [saved], "重载保留完整自定义功能")
checkCustom(!customPreferences.bind([.right, .down], to: .closeWindow), "内置功能不能抢占自定义手势")

var duplicate = CustomActionDraft()
duplicate.name = "另一软件"
duplicate.shortcut = draft.shortcut
duplicate.directions = draft.directions
checkCustom(customPreferences.saveCustomAction(duplicate)?.contains(saved.name) == true, "自定义功能之间的冲突提示占用者")
duplicate.name = saved.name
duplicate.directions = [.left]
checkCustom(customPreferences.saveCustomAction(duplicate) != nil, "同名自定义功能不能重复添加")
checkCustom(customPreferences.bind([.up], to: .missionControl), "可添加独立的内置手势")
duplicate.name = "另一软件"
duplicate.directions = [.up]
checkCustom(customPreferences.saveCustomAction(duplicate)?.contains(GestureAction.missionControl.title) == true,
            "自定义功能不能抢占内置手势")

var edit = CustomActionDraft(action: saved)
edit.name = "新名称"
edit.directions = [.left, .up]
edit.shortcut = .init(keyCode: 105, modifiers: 0, label: "F13")
checkCustom(Preferences(defaults: customDefaults).customActions == [saved], "编辑草稿不改写已保存配置")
checkCustom(customPreferences.saveCustomAction(edit) == nil && customPreferences.customActions.count == 1, "编辑保存替换原记录而非新增")
checkCustom(customPreferences.customAction(for: [.right, .down]) == nil, "更改手势后旧手势失效")
checkCustom(customPreferences.customAction(for: [.left, .up])?.shortcut == edit.shortcut, "新手势解析到编辑后的快捷键")
checkCustom(customPreferences.action(for: [.up]) == .missionControl, "编辑不影响内置功能")

var invalid = edit
invalid.name = " \n "
checkCustom(customPreferences.saveCustomAction(invalid) != nil, "空白名称不能保存")
invalid = edit
invalid.directions = [.up, .up]
checkCustom(customPreferences.saveCustomAction(invalid) != nil, "不能保存识别器不会生成的重复方向")
invalid.directions = [.up, .down, .up, .down, .up]
checkCustom(customPreferences.saveCustomAction(invalid) != nil, "超过四段不能保存")
checkCustom(customPreferences.customActions[0].name == edit.name, "无效编辑不会破坏原记录")
customPreferences.clearCustomGesture(saved.id)
let cleared = customPreferences.customActions[0]
checkCustom(cleared.pattern.isEmpty && cleared.shortcut == edit.shortcut && cleared.name == edit.name, "清除手势保留功能及快捷键")
checkCustom(customPreferences.customAction(for: []) == nil && customPreferences.customAction(for: edit.directions) == nil,
            "已清除的功能不再由任何旧手势触发")
checkCustom(customPreferences.saveCustomAction(edit) == nil, "可以重新录制已清除手势的功能")
customPreferences.restoreDefaults()
checkCustom(customPreferences.customActions.count == 1 && customPreferences.customActions[0].pattern.isEmpty
            && customPreferences.customActions[0].shortcut == edit.shortcut, "重置清除自定义手势但保留名称与快捷键")
customPreferences.deleteCustomAction(saved.id)
checkCustom(Preferences(defaults: customDefaults).customActions.isEmpty, "删除后重载不再出现")
checkCustom(customPreferences.bind(edit.directions, to: .showDesktop), "删除后手势可用于其他功能")

if customFailures.isEmpty { print("自定义功能与持久化测试通过：\(customCount) 项") }
else { customFailures.forEach { print("失败：\($0)") }; exit(1) }
