// Exercise routing with AX identity fixtures; never activate apps or post system input.
private var targetChecks = 0
private func checkTarget(_ condition: @autoclosure () -> Bool, _ message: String) {
    targetChecks += 1
    if !condition() { fatalError(message) }
}
private let targetSuite = "MouseGesture.TargetTests.\(UUID().uuidString)"
private let targetDefaults = UserDefaults(suiteName: targetSuite)!
defer { targetDefaults.removePersistentDomain(forName: targetSuite) }
private let targetPreferences = Preferences(defaults: targetDefaults)
targetPreferences.showTrail = false
_ = targetPreferences.bind([.right], to: .closeTab)
private let backgroundTarget = GestureTarget(pid: 12345, window: AXUIElementCreateApplication(12345))
private let secondWindow = AXUIElementCreateApplication(12346)
checkTarget(backgroundTarget.matches(frontmostPID: 12345, focusedWindow: backgroundTarget.window),
            "目标应用及具体窗口均一致才允许发送快捷键")
checkTarget(!backgroundTarget.matches(frontmostPID: 12345, focusedWindow: secondWindow),
            "同一应用的其他窗口聚焦时不能发送快捷键")
checkTarget(!backgroundTarget.matches(frontmostPID: 12346, focusedWindow: backgroundTarget.window),
            "目标窗口匹配但应用不在前台时不能发送快捷键")
checkTarget(!backgroundTarget.matches(frontmostPID: 12345, focusedWindow: nil), "没有聚焦窗口时不能发送快捷键")

private var targetLookups: [CGPoint] = []
private var nextTarget: GestureTarget? = backgroundTarget
private var targetFrontmost: NSRunningApplication? = .current
private let targetMonitor = GestureMonitor(preferences: targetPreferences, frontmostApplication: { targetFrontmost },
                                          captureTarget: { point in
    targetLookups.append(point)
    return nextTarget.map(fixtureRequest)
}, lookupTarget: fixtureLookup, workspaceNotifications: gestureTestNotifications)
private var recognizedTargets: [GestureTarget] = []
targetMonitor.onRecognized = { _, target in recognizedTargets.append(target) }
checkTarget(targetMonitor.sendTrailEvent(.rightMouseDown, x: 100), "后台窗口也能开始手势")
nextTarget = fixtureGestureTarget
_ = targetMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
_ = targetMonitor.sendTrailEvent(.rightMouseUp, x: 220)
drainTrailQueue()
checkTarget(recognizedTargets.count == 1 && recognizedTargets[0].pid == backgroundTarget.pid,
            "后台窗口手势不会错误路由到当前聚焦应用")
checkTarget(CFEqual(recognizedTargets[0].window, backgroundTarget.window), "识别回调保留起点窗口身份")
checkTarget(targetLookups == [CGPoint(x: 100, y: 100)], "跨窗口拖动或松开不会重新选择目标")

nextTarget = nil
checkTarget(!targetMonitor.sendTrailEvent(.rightMouseDown, x: 100), "找不到鼠标下窗口时原样放行右键按下")
checkTarget(!targetMonitor.sendTrailEvent(.rightMouseUp, x: 100), "找不到窗口时原样放行松开且不回退到聚焦应用")
nextTarget = backgroundTarget
_ = targetMonitor.sendTrailEvent(.rightMouseDown, x: 100)
_ = targetMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
targetFrontmost = nil
_ = targetMonitor.sendTrailEvent(.rightMouseUp, x: 220)
drainTrailQueue()
checkTarget(recognizedTargets.count == 1, "绘制时用户切换前台应用仍取消手势")
targetFrontmost = .current
_ = targetMonitor.sendTrailEvent(.rightMouseDown, x: 100)
_ = targetMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
_ = targetMonitor.sendTrailEvent(.rightMouseUp, x: 220)
let completedStrokeID = targetMonitor.currentStrokeID
_ = targetMonitor.sendTrailEvent(.leftMouseDown, x: 220)
drainTrailQueue()
checkTarget(targetMonitor.currentStrokeID != completedStrokeID && recognizedTargets.count == 1,
            "松开后用户点击会取消排队操作及等待激活的快捷键")

if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier != nil }) {
    nextTarget = GestureTarget(pid: app.processIdentifier, window: AXUIElementCreateApplication(app.processIdentifier))
    targetPreferences.excludedBundleIDs = app.bundleIdentifier!
    checkTarget(!targetMonitor.sendTrailEvent(.rightMouseDown, x: 100), "排除规则检查鼠标下窗口所属应用")
    targetPreferences.excludedBundleIDs = ""
}
targetPreferences.clearGesture(for: .closeTab)
_ = targetPreferences.bind([.right], to: .showDesktop)
let desktopTarget = GestureTarget(pid: NSRunningApplication.current.processIdentifier, window: nil)
checkTarget(!desktopTarget.isAvailable && !desktopTarget.matches(frontmostPID: desktopTarget.pid,
                                                                focusedWindow: backgroundTarget.window),
            "没有普通窗口的桌面目标不能用于窗口操作")
nextTarget = desktopTarget
let recognizedBeforeDesktop = recognizedTargets.count
_ = targetMonitor.sendTrailEvent(.rightMouseDown, x: 100)
_ = targetMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
_ = targetMonitor.sendTrailEvent(.rightMouseUp, x: 220)
drainTrailQueue()
checkTarget(recognizedTargets.count == recognizedBeforeDesktop + 1 && recognizedTargets.last?.window == nil,
            "桌面没有普通窗口时仍可完成系统手势")
targetMonitor.stop()

private var desktopTestsFinished = false
Task { @MainActor in
    var sent: [KeyboardShortcut] = []
    let sender: ActionExecutor.ShortcutSender = { shortcut, title, pid in
        checkTarget(pid == nil && title == GestureAction.showDesktop.title,
                    "显示桌面直接发送全局快捷键，不要求或激活目标窗口")
        sent.append(shortcut)
        return "测试已发送"
    }
    // A non-existent window must not block the first toggle or restoring from the desktop.
    for target in [backgroundTarget, desktopTarget] {
        let result = await ActionExecutor.execute(.showDesktop, preferences: targetPreferences, target: target,
                                                  isCurrent: { true }, permissionCheck: { true }, sendShortcut: sender)
        checkTarget(result == "测试已发送", "隐藏窗口和桌面上再次触发均发送一次切换快捷键")
    }
    checkTarget(sent.count == 2 && sent.allSatisfy { $0 == KeyboardShortcut.standard(for: .showDesktop) },
                "连续两次显示桌面发送相同 F11，不插入窗口聚焦步骤")
    _ = await ActionExecutor.execute(.showDesktop, preferences: targetPreferences, target: desktopTarget,
                                     isCurrent: { false }, permissionCheck: { true }, sendShortcut: sender)
    _ = await ActionExecutor.execute(.showDesktop, preferences: targetPreferences, target: desktopTarget,
                                     isCurrent: { true }, permissionCheck: { false }, sendShortcut: sender)
    checkTarget(sent.count == 2, "手势已取消或无权限时不发送全局快捷键")
    for action: GestureAction in [.closeWindow, .closeTab] {
        let result = await ActionExecutor.execute(action, preferences: targetPreferences, target: desktopTarget,
                                                  isCurrent: { true }, permissionCheck: { true }, sendShortcut: sender)
        checkTarget(result == "手势目标窗口已失效，本次操作已取消" && sent.count == 2,
                    "桌面无窗口时不把关闭窗口或标签页动作发送到其他窗口")
    }
    desktopTestsFinished = true
}
private let desktopTestsDeadline = Date().addingTimeInterval(2)
while !desktopTestsFinished && Date() < desktopTestsDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
}
checkTarget(desktopTestsFinished, "显示桌面异步执行检查完成")
print("手势目标窗口测试通过：\(targetChecks) 项")
