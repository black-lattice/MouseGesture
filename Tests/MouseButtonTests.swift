private var mouseChecks = 0
private func checkMouse(_ condition: @autoclosure () -> Bool, _ message: String) {
    mouseChecks += 1
    if !condition() { fatalError(message) }
}
private func mouseEvent(_ type: CGEventType, number: Int64 = 2, x: CGFloat = 100, tagged: Bool = false) -> CGEvent {
    let event = CGEvent(mouseEventSource: nil, mouseType: type,
                        mouseCursorPosition: CGPoint(x: x, y: 100), mouseButton: CGMouseButton(rawValue: UInt32(number))!)!
    event.setIntegerValueField(.mouseEventButtonNumber, value: number)
    event.flags = []
    if tagged { event.setIntegerValueField(.eventSourceUserData, value: ActionExecutor.eventTag) }
    return event
}
private let mouseTestSuite = "MouseGesture.MouseEvents.\(UUID().uuidString)"
private let mouseTestDefaults = UserDefaults(suiteName: mouseTestSuite)!
defer { mouseTestDefaults.removePersistentDomain(forName: mouseTestSuite) }
private let mouseTestPreferences = Preferences(defaults: mouseTestDefaults)
private var mouseFrontmost: NSRunningApplication? = .current
private let mouseMonitor = MouseButtonMonitor(preferences: mouseTestPreferences, frontmostApplication: { mouseFrontmost })
private let boundMouseShortcut = KeyboardShortcut(keyCode: 8, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘ C")
private var clickedButtons: [MouseButton] = []
mouseMonitor.onClick = { button, shortcut, pid in
    checkMouse(shortcut == boundMouseShortcut && pid == NSRunningApplication.current.processIdentifier,
               "传递已绑定快捷键与按下时的目标应用")
    clickedButtons.append(button)
}
@discardableResult
private func sendMouse(_ type: CGEventType, number: Int64 = 2, x: CGFloat = 100, tagged: Bool = false) -> Bool {
    mouseMonitor.handle(type: type, event: mouseEvent(type, number: number, x: x, tagged: tagged))
}
for number: Int64 in [2, 3, 4, 8] {
    checkMouse(!sendMouse(.otherMouseDown, number: number) && !sendMouse(.otherMouseUp, number: number),
               "未绑定的按键原样放行")
}
for button in MouseButton.allCases {
    mouseTestPreferences.setMouseShortcut(boundMouseShortcut, for: button)
    checkMouse(sendMouse(.otherMouseDown, number: button.defaultNumber), "绑定后拦截按下")
    let count = clickedButtons.count
    drainTrailQueue()
    checkMouse(clickedButtons.count == count, "按住期间不执行快捷键")
    checkMouse(sendMouse(.otherMouseUp, number: button.defaultNumber), "绑定后拦截松开")
    drainTrailQueue()
    checkMouse(clickedButtons.count == count + 1 && clickedButtons.last == button, "三种按键各执行一次")
    checkMouse(!sendMouse(.otherMouseUp, number: button.defaultNumber), "孤立松开不重复触发")
}
let clicksBeforeCancelTests = clickedButtons.count
_ = sendMouse(.otherMouseDown)
checkMouse(sendMouse(.otherMouseDragged, x: 120), "绑定按键拖动不会泄漏到目标应用")
_ = sendMouse(.otherMouseDragged, x: 100)
_ = sendMouse(.otherMouseUp)
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "拖出阈值再返回不误判点击")

_ = sendMouse(.otherMouseDown)
mouseMonitor.cancel()
checkMouse(sendMouse(.otherMouseUp), "取消后继续吞掉匹配的松开")
_ = sendMouse(.otherMouseDown)
_ = sendMouse(.otherMouseUp)
mouseMonitor.cancel()
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "取消进行中及排队的点击均不执行")

mouseMonitor.suspended = true
checkMouse(!sendMouse(.otherMouseDown) && !sendMouse(.otherMouseUp), "录制期间鼠标原样放行")
mouseMonitor.suspended = false
_ = sendMouse(.otherMouseDown)
mouseMonitor.suspended = true
checkMouse(sendMouse(.otherMouseUp), "录制开始前已接管的按键仍正确收尾")
mouseMonitor.suspended = false

mouseTestPreferences.enabled = false
checkMouse(!sendMouse(.otherMouseDown) && !sendMouse(.otherMouseUp), "关闭总开关后不接管")
mouseTestPreferences.enabled = true
_ = sendMouse(.otherMouseDown)
mouseTestPreferences.enabled = false
checkMouse(sendMouse(.otherMouseUp), "关闭总开关取消进行中的点击")
mouseTestPreferences.enabled = true
_ = sendMouse(.otherMouseDown)
mouseFrontmost = nil
checkMouse(sendMouse(.otherMouseUp), "目标应用变化后取消点击但吞掉松开")
checkMouse(!sendMouse(.otherMouseDown), "没有前台应用时不接管")
mouseFrontmost = .current
_ = sendMouse(.otherMouseDown)
_ = sendMouse(.otherMouseUp)
mouseFrontmost = nil
drainTrailQueue()
mouseFrontmost = .current
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "排队执行前再次确认前台应用")

_ = sendMouse(.otherMouseDown)
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
_ = sendMouse(.otherMouseUp)
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "按住时切到其他应用再返回也取消")
_ = sendMouse(.otherMouseDown)
_ = sendMouse(.otherMouseUp)
NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "排队期间切换应用再返回也取消")

_ = sendMouse(.otherMouseDown)
mouseTestPreferences.setMouseShortcut(nil, for: .middle)
checkMouse(sendMouse(.otherMouseUp), "清除绑定时取消进行中的点击")
mouseTestPreferences.setMouseShortcut(boundMouseShortcut, for: .middle)
_ = sendMouse(.otherMouseDown)
_ = sendMouse(.otherMouseUp)
mouseTestPreferences.setMouseShortcut(nil, for: .middle)
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests, "排队后清除绑定不执行过期操作")
mouseTestPreferences.setMouseShortcut(boundMouseShortcut, for: .middle)
checkMouse(!sendMouse(.otherMouseDown, tagged: true) && !sendMouse(.otherMouseUp, tagged: true), "标记的补发事件不接管")

// Recover a missing up, permit small hand jitter, and use remapped physical buttons.
_ = sendMouse(.otherMouseDown)
mouseMonitor.cancel()
_ = sendMouse(.otherMouseDown)
_ = sendMouse(.otherMouseDragged, x: 103)
_ = sendMouse(.otherMouseUp, x: 103)
drainTrailQueue()
checkMouse(clickedButtons.count == clicksBeforeCancelTests + 1, "新按下恢复丢失松开状态且容忍小幅抖动")
mouseTestPreferences.setMouseButtonNumber(8, for: .forward)
checkMouse(!sendMouse(.otherMouseDown, number: 4) && !sendMouse(.otherMouseUp, number: 4), "重新识别后旧编号恢复原生行为")
_ = sendMouse(.otherMouseDown, number: 8)
_ = sendMouse(.otherMouseUp, number: 8)
drainTrailQueue()
checkMouse(clickedButtons.last == .forward && clickedButtons.count == clicksBeforeCancelTests + 2, "非标准侧键执行对应操作")

// Use an installed app solely as a bundle-ID fixture; never activate or send it input.
if let fixture = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier != nil }) {
    mouseFrontmost = fixture
    mouseTestPreferences.excludedBundleIDs = fixture.bundleIdentifier!
    checkMouse(!sendMouse(.otherMouseDown) && !sendMouse(.otherMouseUp), "排除应用保留鼠标原功能")
    mouseTestPreferences.excludedBundleIDs = ""
    _ = sendMouse(.otherMouseDown)
    mouseTestPreferences.excludedBundleIDs = fixture.bundleIdentifier!
    checkMouse(sendMouse(.otherMouseUp), "按住期间排除应用会取消动作")
    drainTrailQueue()
    checkMouse(clickedButtons.count == clicksBeforeCancelTests + 2, "被排除的动作不执行")
    mouseTestPreferences.excludedBundleIDs = ""
}
mouseFrontmost = .current

extension GestureMonitor {
    fileprivate func testMouseRouting() {
        preferences.setMouseShortcut(boundMouseShortcut, for: .middle)
        var clicks = 0
        mouseButtons.onClick = { _, _, _ in clicks += 1 }
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        cancel()
        checkMouse(handle(type: .otherMouseDown, event: mouseEvent(.otherMouseDown, number: 9)) != nil,
                   "右键取消等待松开时不吞掉未绑定侧键")
        checkMouse(handle(type: .otherMouseDown, event: mouseEvent(.otherMouseDown)) == nil, "主监听器路由中键按下")
        checkMouse(handle(type: .otherMouseUp, event: mouseEvent(.otherMouseUp)) == nil, "主监听器路由中键松开")
        drainTrailQueue()
        checkMouse(clicks == 1, "中键不受右键收尾状态影响")
        _ = sendTrailEvent(.rightMouseUp, x: 100)
        _ = handle(type: .otherMouseDown, event: mouseEvent(.otherMouseDown))
        gestureTestNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        _ = handle(type: .otherMouseUp, event: mouseEvent(.otherMouseUp))
        drainTrailQueue()
        checkMouse(clicks == 1, "切换桌面取消中键点击")
        stop()
    }
}
GestureMonitor(preferences: mouseTestPreferences, frontmostApplication: { .current },
               captureTarget: { _ in fixtureRequest(fixtureGestureTarget) }, lookupTarget: fixtureLookup, workspaceNotifications: gestureTestNotifications).testMouseRouting()

let mouseRecordingState = AppState(preferences: mouseTestPreferences, usesSystemShortcutCapture: false)
mouseRecordingState.recordMouseShortcut(.middle)
checkMouse(mouseRecordingState.monitor.suspended && mouseRecordingState.recordingMouseShortcut == .middle, "鼠标快捷键录制暂停动作")
application.sendEvent(key(0, [], "a"))
checkMouse(mouseRecordingState.mouseRecordingError != nil && mouseRecordingState.recordingMouseShortcut == .middle, "无效快捷键提示后继续录制")
application.sendEvent(key(35, [.command, .option], "p"))
checkMouse(mouseTestPreferences.mouseBinding(for: .middle).shortcut?.keyCode == 35
           && mouseRecordingState.recordingMouseShortcut == nil && !mouseRecordingState.monitor.suspended, "有效快捷键自动保存并结束录制")
mouseRecordingState.recordMouseShortcut(.middle)
application.sendEvent(escape)
checkMouse(mouseTestPreferences.mouseBinding(for: .middle).shortcut?.keyCode == 35
           && mouseRecordingState.recordingMouseShortcut == nil, "Esc 取消不覆盖已保存的快捷键")
mouseRecordingState.recordMouseButton(.back)
checkMouse(mouseRecordingState.monitor.suspended && mouseRecordingState.recordingMouseButton == .back, "识别物理按键暂停动作")
application.sendEvent(NSEvent(cgEvent: mouseEvent(.otherMouseDown, number: 7))!)
checkMouse(mouseRecordingState.recordingMouseButton == .back, "按下后等待松开完成识别")
application.sendEvent(NSEvent(cgEvent: mouseEvent(.otherMouseUp, number: 7))!)
checkMouse(mouseTestPreferences.mouseBinding(for: .back).buttonNumber == 7
           && mouseRecordingState.recordingMouseButton == nil && !mouseRecordingState.monitor.suspended, "本地按键录入新编号并恢复监听")
mouseRecordingState.recordMouseButton(.forward)
mouseRecordingState.recordGesture(.copy)
checkMouse(mouseRecordingState.recordingMouseButton == nil && mouseRecordingState.gestureRecordingAction == .copy, "手势录制与按键识别互斥")
mouseRecordingState.recordMouseShortcut(.forward)
checkMouse(mouseRecordingState.gestureRecordingAction == nil, "鼠标快捷键录制停止手势录制")
mouseRecordingState.stopRecording()
application.sendEvent(key(8, [.command], "c"))
checkMouse(mouseTestPreferences.mouseBinding(for: .forward).shortcut == boundMouseShortcut, "停止录制后不会残留键盘捕获")
mouseRecordingState.stop()
print("鼠标按键事件与录制测试通过：\(mouseChecks) 项")
