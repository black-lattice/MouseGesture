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
                                          targetAtPoint: { point in
    targetLookups.append(point)
    return nextTarget
})
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
targetMonitor.stop()
print("手势目标窗口测试通过：\(targetChecks) 项")
