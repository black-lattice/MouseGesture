private let triggerSuite = "MouseGesture.TriggerTests.\(UUID().uuidString)"
private let triggerDefaults = UserDefaults(suiteName: triggerSuite)!
defer { triggerDefaults.removePersistentDomain(forName: triggerSuite) }
private let triggerPreferences = Preferences(defaults: triggerDefaults)
triggerPreferences.showTrail = false
triggerPreferences.showHint = false
triggerPreferences.bind([.right], to: .showDesktop)
private var triggerRecognized = 0
private var triggerReplays: [CGEvent] = []
private var triggerChecks = 0
private func checkTrigger(_ condition: @autoclosure () -> Bool, _ message: String) {
    triggerChecks += 1
    if !condition() { fatalError(message) }
}
private let triggerMonitor = GestureMonitor(preferences: triggerPreferences, frontmostApplication: { .current },
    captureTarget: { _ in fixtureRequest(fixtureGestureTarget) }, lookupTarget: fixtureLookup,
    postEvent: { triggerReplays.append($0) }, workspaceNotifications: NotificationCenter())
triggerMonitor.onRecognized = { _, _ in triggerRecognized += 1 }
extension GestureMonitor {
    fileprivate func sendButtonTest(_ type: CGEventType, number: Int64, x: CGFloat, flags: CGEventFlags = []) -> Bool {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: x, y: 100),
                            mouseButton: CGMouseButton(rawValue: UInt32(number))!)!
        event.flags = flags
        event.setIntegerValueField(.mouseEventButtonNumber, value: number)
        return handle(type: type, event: event) == nil
    }
}
for number: Int64 in [2, 3, 4, 8] {
    triggerPreferences.triggerButton = number
    let before = triggerRecognized
    checkTrigger(!triggerMonitor.sendButtonTest(.rightMouseDown, number: 1, x: 100), "使用其他绘制键时右键按下原样放行")
    checkTrigger(!triggerMonitor.sendButtonTest(.rightMouseUp, number: 1, x: 100), "使用其他绘制键时右键松开原样放行")
    checkTrigger(triggerMonitor.sendButtonTest(.otherMouseDown, number: number, x: 100), "接管所选绘制键按下")
    _ = triggerMonitor.sendButtonTest(.otherMouseDragged, number: number, x: 220)
    _ = triggerMonitor.sendButtonTest(.otherMouseUp, number: number, x: 220)
    drainTrailQueue()
    checkTrigger(triggerRecognized == before + 1, "中键或侧键绘制只触发一次动作")
    triggerReplays = []
    _ = triggerMonitor.sendButtonTest(.otherMouseDown, number: number, x: 100)
    _ = triggerMonitor.sendButtonTest(.otherMouseUp, number: number, x: 100)
    drainTrailQueue()
    checkTrigger(triggerReplays.map(\.type) == [.otherMouseDown, .otherMouseUp]
        && triggerReplays.allSatisfy { $0.getIntegerValueField(.mouseEventButtonNumber) == number }, "普通点击回放保持原始按键类型和编号")
    checkTrigger(!triggerMonitor.sendButtonTest(.otherMouseDown, number: number, x: 100, flags: .maskAlternate), "Option 绕过所选绘制键")
    checkTrigger(!triggerMonitor.sendButtonTest(.otherMouseUp, number: number, x: 100, flags: .maskAlternate), "绕过后松开原样放行")
    _ = triggerMonitor.sendButtonTest(.otherMouseDown, number: number, x: 100)
    _ = triggerMonitor.sendButtonTest(.otherMouseDragged, number: number, x: 220)
    triggerMonitor.cancel()
    checkTrigger(triggerMonitor.sendButtonTest(.otherMouseUp, number: number, x: 220), "取消后吞掉被接管按键的松开")
    drainTrailQueue()
    checkTrigger(triggerRecognized == before + 1, "取消的中键和侧键手势不执行")
}
triggerPreferences.triggerButton = 2
triggerPreferences.setMouseShortcut(.standard(for: .copy), for: .middle)
checkTrigger(!triggerMonitor.mouseButtons.handle(type: .otherMouseDown, event: {
    let event = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: .zero, mouseButton: .center)!
    event.setIntegerValueField(.mouseEventButtonNumber, value: 2)
    return event
}()), "作为绘制键的中键不会同时进入快捷键处理")
triggerPreferences.triggerButton = 1
checkTrigger(triggerMonitor.sendButtonTest(.rightMouseDown, number: 1, x: 100), "切回右键后恢复右键绘制")
_ = triggerMonitor.sendButtonTest(.rightMouseUp, number: 1, x: 100)
drainTrailQueue()
print("可选绘制键、点击回放与互斥测试通过：\(triggerChecks) 项")
