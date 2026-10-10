// Native view event tests: no visible windows, global event injection, or settings changes.
let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
private let pad = RecordingPadView(frame: NSRect(x: 0, y: 0, width: 400, height: 160))
window.contentView = pad
var result: [Direction]?
var started = 0
var completed = 0
var cancelled = false
pad.onStart = { started += 1; result = nil }
pad.onComplete = { result = $0; completed += 1 }
pad.onCancel = { cancelled = true }
var testCount = 0
var failures: [String] = []
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    testCount += 1
    if !condition() { failures.append(name) }
}
func draw(_ points: [CGPoint]) {
    for (index, point) in points.enumerated() {
        let type: NSEvent.EventType = index == 0 ? .rightMouseDown : (index == points.count - 1 ? .rightMouseUp : .rightMouseDragged)
        let event = NSEvent.mouseEvent(with: type, location: pad.convert(point, to: nil), modifierFlags: [],
                                      timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                      context: nil, eventNumber: index, clickCount: 1, pressure: 1)!
        switch type {
        case .rightMouseDown: pad.rightMouseDown(with: event)
        case .rightMouseUp: pad.rightMouseUp(with: event)
        default: pad.rightMouseDragged(with: event)
        }
    }
}
draw([CGPoint(x: 40, y: 20), CGPoint(x: 40, y: 70), CGPoint(x: 40, y: 130)])
expect(result == [.down], "录制区域向下与全局 Quartz 方向一致")
expect(started == 1 && completed == 1, "一笔手势仅开始和完成一次")
draw([CGPoint(x: 40, y: 130), CGPoint(x: 40, y: 20), CGPoint(x: 150, y: 20), CGPoint(x: 150, y: 130)])
expect(result == [.up, .right, .down], "录制原预设之外的三段折线")
draw([CGPoint(x: 40, y: 40), CGPoint(x: 45, y: 45)])
expect(result == nil, "普通点击及抖动不能成为录制结果")
draw([CGPoint(x: 40, y: 20), CGPoint(x: 140, y: 120)])
expect(result == nil, "斜线无效，不能保留上一笔的结果")
draw([CGPoint(x: 40, y: 20), CGPoint(x: 40, y: 180), CGPoint(x: 40, y: 130)])
expect(result == nil, "移出录制区域再返回也不能保存")
pad.minimumLength = 140
draw([CGPoint(x: 40, y: 20), CGPoint(x: 140, y: 20)])
expect(result == nil, "录制与实际识别使用相同的最短长度")
draw([CGPoint(x: 40, y: 20), CGPoint(x: 240, y: 20)])
expect(result == [.right], "无效后可重新绘制有效手势")
let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                              charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
pad.keyDown(with: escape)
expect(cancelled, "Esc 退出录制")

let state = AppState(usesSystemShortcutCapture: false)
state.recordGesture(.showDesktop)
expect(state.monitor.suspended && state.gestureRecordingAction == .showDesktop, "录制手势时暂停动作执行")
state.editCustomAction()
state.recordCustomShortcut()
expect(state.gestureRecordingAction == nil && state.recordingCustomShortcut && state.monitor.suspended,
       "切换键盘录制时清除手势录制状态并保持暂停")
state.recordGesture(.closeWindow)
expect(!state.recordingCustomShortcut && state.gestureRecordingAction == .closeWindow, "手势和快捷键录制互斥")
state.stopRecording()
expect(!state.monitor.suspended && state.gestureRecordingAction == nil && !state.recordingCustomShortcut,
       "结束录制后恢复监听状态")

let draftSuite = "MouseGesture.RecordingTests.\(UUID().uuidString)"
let draftDefaults = UserDefaults(suiteName: draftSuite)!
defer { draftDefaults.removePersistentDomain(forName: draftSuite) }
let editorState = AppState(preferences: Preferences(defaults: draftDefaults), usesSystemShortcutCapture: false)
editorState.editCustomAction()
expect(editorState.customDraft != nil && editorState.monitor.suspended, "打开自定义编辑器即暂停手势动作")
editorState.customDraft?.name = "软件操作"
editorState.recordCustomShortcut()
expect(editorState.recordingCustomShortcut && editorState.customDraft != nil, "开始快捷键录入不会丢失草稿")
func key(_ code: UInt16, _ flags: NSEvent.ModifierFlags, _ characters: String) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, characters: characters,
                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
}
application.sendEvent(key(0, [], "a"))
expect(editorState.recordingCustomShortcut && editorState.customDraft?.shortcut == nil
       && editorState.customDraft?.shortcutError != nil, "无效按键提示错误并继续等待有效快捷键")
application.sendEvent(key(35, [.command, .option], "p"))
expect(editorState.customDraft?.shortcut?.keyCode == 35 && !editorState.recordingCustomShortcut,
       "本地键盘事件录入草稿快捷键并结束捕获")
expect(editorState.monitor.suspended && editorState.preferences.customActions.isEmpty, "录入快捷键后仍暂停，且保存前不生效")
editorState.recordCustomShortcut()
application.sendEvent(escape)
expect(!editorState.recordingCustomShortcut && editorState.customDraft?.shortcut?.keyCode == 35
       && editorState.monitor.suspended, "取消重录快捷键保留之前的草稿内容并继续暂停动作")
editorState.customDraft?.directions = [.right, .down]
editorState.stopRecording()
expect(editorState.customDraft == nil && !editorState.monitor.suspended && editorState.preferences.customActions.isEmpty,
       "取消自定义草稿不留配置并恢复手势")
editorState.editCustomAction()
editorState.recordCustomShortcut()
editorState.recordGesture(.spotlight)
expect(editorState.customDraft == nil && !editorState.recordingCustomShortcut && editorState.gestureRecordingAction == .spotlight,
       "切换内置手势录制会结束自定义快捷键捕获")
application.sendEvent(key(49, [.control, .command], " "))
expect(editorState.preferences.shortcut(for: .spotlight) == KeyboardShortcut.standard(for: .spotlight)
       && editorState.preferences.shortcuts.isEmpty, "内置功能录制期间按组合键不会修改其快捷键")
application.sendEvent(escape)
expect(KeyboardShortcut.recorded(from: key(0, [], "a")) == nil, "普通打字不误录为快捷键")
expect(KeyboardShortcut.recorded(from: key(105, [], ""))?.label == "F13", "支持软件常用 F13 等功能键")
expect(KeyboardShortcut.isCancel(escape) && KeyboardShortcut.recorded(from: escape) == nil, "单独 Esc 用于取消")
expect(KeyboardShortcut.recorded(from: key(53, [.command, .option], "\u{1b}"))?.label == "⌥ ⌘ Esc",
       "带修饰键的 Esc 可以作为软件快捷键")
let shortcut = KeyboardShortcut.recorded(from: key(35, [.command, .option], "p"))!
let events = ActionExecutor.makeShortcutEvents(shortcut)!
expect(events.map(\.type) == [.keyDown, .keyUp] && events.allSatisfy { $0.getIntegerValueField(.keyboardEventKeycode) == 35 },
       "发送事件使用录入的物理键位且包含按下和松开")
expect(events.allSatisfy { $0.flags.contains([.maskCommand, .maskAlternate]) && !$0.flags.contains(.maskControl)
    && $0.getIntegerValueField(.eventSourceUserData) == ActionExecutor.eventTag }, "保留自定义修饰键和防重入标记")
let functionEvents = ActionExecutor.makeShortcutEvents(.init(keyCode: 103, modifiers: 0, label: "F11"))!
expect(functionEvents.allSatisfy { $0.flags.contains(.maskSecondaryFn) }, "自定义功能键保留系统功能键标记")
let rows = AppState(preferences: Preferences(defaults: draftDefaults), usesSystemShortcutCapture: false)
expect(rows.customDrafts.count == 1 && rows.customDraft == nil && !rows.monitor.suspended,
       "默认空白行不会暂停正常手势")
let firstRowID = rows.customDrafts[0].id
rows.customDrafts[0].name = "第一行"
rows.addCustomDraft()
let secondRowID = rows.customDrafts[1].id
rows.customDrafts[1].name = "第二行"
expect(rows.customDrafts.count == 2 && firstRowID != secondRowID && rows.customDrafts[0].name == "第一行",
       "加号追加独立空白行并保留原行输入")
rows.activateCustomDraft(firstRowID)
rows.recordCustomShortcut()
application.sendEvent(key(35, [.command, .option], "p"))
expect(rows.customDrafts[0].shortcut?.keyCode == 35 && rows.customDrafts[1].shortcut == nil,
       "录入快捷键仅更新当前行")
rows.customDraft?.directions = [.left, .up]
rows.activateCustomDraft(secondRowID)
rows.recordCustomShortcut()
application.sendEvent(key(0, [.command, .control], "a"))
expect(rows.customDrafts[1].shortcut?.keyCode == 0 && rows.customDrafts[0].shortcut?.keyCode == 35
       && rows.customDrafts[0].directions == [.left, .up], "切换录制行不覆盖其他草稿")
rows.customDraft?.directions = [.right, .up]
rows.stopRecording()
expect(rows.customDrafts.count == 2 && !rows.monitor.suspended && rows.preferences.customActions.isEmpty,
       "结束录制保留多行草稿但保存前不会生效")
expect(rows.preferences.saveCustomAction(rows.customDrafts[0]) == nil, "第一行可独立保存")
rows.removeCustomDraft(firstRowID)
expect(rows.customDrafts.count == 1 && rows.customDrafts[0].id == secondRowID
       && rows.customDrafts[0].directions == [.right, .up], "保存移除本行草稿且保留其他待填行")
rows.customDrafts[0].directions = [.left, .up]
expect(rows.preferences.validationError(for: rows.customDrafts[0])?.contains("第一行") == true,
       "其他行保存后重新检查跨行手势冲突")
rows.customDrafts[0].directions = [.right, .up]
expect(rows.preferences.saveCustomAction(rows.customDrafts[0]) == nil, "第二行独立保存且不覆盖第一行")
rows.removeCustomDraft(secondRowID)
expect(rows.preferences.customActions.count == 2 && rows.customDrafts.isEmpty
       && !rows.monitor.suspended, "已有自定义功能时保存最后一行不补空白行")
rows.addCustomDraft()
rows.removeCustomDraft(rows.customDrafts[0].id)
expect(rows.customDrafts.isEmpty && rows.preferences.customActions.count == 2, "已有功能时可以删除最后一个空白草稿")
rows.addCustomDraft()
rows.resetCustomDrafts()
expect(rows.customDrafts.isEmpty, "关闭再打开设置不会补回已删除的空白行")
let reopenedRows = AppState(preferences: Preferences(defaults: draftDefaults), usesSystemShortcutCapture: false)
expect(reopenedRows.customDrafts.isEmpty, "已有持久化自定义功能时启动不创建空白行")
let savedRow = rows.preferences.customActions[0]
rows.editCustomAction(savedRow)
rows.customDraft?.name = "未保存的改名"
rows.editCustomAction(savedRow)
expect(rows.customDrafts.filter { $0.id == savedRow.id }.count == 1 && rows.customDraft?.name == "未保存的改名",
       "再次编辑同一功能复用草稿而不重复创建")
rows.removeCustomDraft(savedRow.id)
expect(rows.preferences.customActions[0].name == "第一行" && !rows.monitor.suspended,
       "取消编辑仅移除该行草稿且不改动已保存功能")
for action in rows.preferences.customActions { rows.preferences.deleteCustomAction(action.id) }
rows.ensureCustomDraft()
expect(rows.customDrafts.count == 1 && rows.customDrafts[0].name.isEmpty, "删除所有自定义功能后恢复默认空白行")
rows.removeCustomDraft(rows.customDrafts[0].id)
expect(rows.customDrafts.count == 1 && rows.customDrafts[0].name.isEmpty, "没有自定义功能时仍保留一个空白入口")
window.close()
if failures.isEmpty { print("手势录制与状态测试通过：\(testCount) 项") }
else { failures.forEach { print("失败：\($0)") }; exit(1) }
