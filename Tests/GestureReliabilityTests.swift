// Deterministic event/lookup interleavings; never post input or activate applications.
private var reliabilityChecks = 0
private func checkReliability(_ condition: @autoclosure () -> Bool, _ message: String) {
    reliabilityChecks += 1
    precondition(condition(), message)
}
private let reliabilitySuite = "MouseGesture.Reliability.\(UUID().uuidString)"
private let reliabilityDefaults = UserDefaults(suiteName: reliabilitySuite)!
defer { reliabilityDefaults.removePersistentDomain(forName: reliabilitySuite) }
private let reliabilityPreferences = Preferences(defaults: reliabilityDefaults)
reliabilityPreferences.showTrail = false
_ = reliabilityPreferences.bind([.right], to: .closeTab)
private var resolutions = 0
private var pendingLookup: ((GestureTarget?) -> Void)?
private var replayed: [CGEvent] = []
private let reliabilityRequest = GestureTargetRequest(pid: fixtureGestureTarget.pid, resolve: {
    resolutions += 1
    return fixtureGestureTarget
})
private let reliabilityMonitor = GestureMonitor(preferences: reliabilityPreferences, frontmostApplication: { .current },
    captureTarget: { _ in reliabilityRequest }, lookupTarget: { _, completion in
        pendingLookup = completion
        return nil
    }, postEvent: { replayed.append($0) }, workspaceNotifications: gestureTestNotifications)
private var reliabilityRecognized = 0
reliabilityMonitor.onRecognized = { _, _ in reliabilityRecognized += 1 }
private func drawReliability() {
    _ = reliabilityMonitor.sendTrailEvent(.rightMouseDown, x: 100)
    _ = reliabilityMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
    _ = reliabilityMonitor.sendTrailEvent(.rightMouseUp, x: 220)
    drainTrailQueue()
}
_ = reliabilityMonitor.sendTrailEvent(.rightMouseDown, x: 100)
_ = reliabilityMonitor.sendTrailEvent(.rightMouseUp, x: 100)
drainTrailQueue()
checkReliability(resolutions == 0 && pendingLookup == nil && replayed.count == 2,
                 "普通右键点击无需 AX 查询，完整回放按下和松开")
checkReliability(replayed.allSatisfy { $0.getIntegerValueField(.eventSourceUserData) == ActionExecutor.eventTag },
                 "普通点击回放带标记，避免再次拦截")
drawReliability()
checkReliability(resolutions == 0 && pendingLookup != nil && reliabilityRecognized == 0,
                 "事件处理不执行 AX 查询，松开后等待异步窗口结果")
pendingLookup?(fixtureGestureTarget)
checkReliability(reliabilityRecognized == 1, "窗口查询完成后执行一次")
drawReliability()
let cancelledLookup = pendingLookup
reliabilityMonitor.cancel()
cancelledLookup?(fixtureGestureTarget)
checkReliability(reliabilityRecognized == 1, "取消后迟到的窗口查询不执行操作")
drawReliability()
let previousLookup = pendingLookup
_ = reliabilityMonitor.sendTrailEvent(.rightMouseDown, x: 100)
previousLookup?(fixtureGestureTarget)
checkReliability(reliabilityRecognized == 1, "上一笔查询结果不能影响下一笔")
reliabilityMonitor.cancel()

drawReliability()
let beforeActivation = reliabilityMonitor.currentStrokeID
let workspaceNotifications = gestureTestNotifications
workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
pendingLookup?(fixtureGestureTarget)
checkReliability(reliabilityMonitor.currentStrokeID != beforeActivation && reliabilityRecognized == 1,
                 "等待查询时应用切换立即取消，不因切回原应用恢复")
_ = reliabilityMonitor.sendTrailEvent(.rightMouseDown, x: 100)
_ = reliabilityMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
let drawingID = reliabilityMonitor.currentStrokeID
workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
_ = reliabilityMonitor.sendTrailEvent(.rightMouseUp, x: 220)
drainTrailQueue()
checkReliability(reliabilityMonitor.currentStrokeID != drawingID && reliabilityRecognized == 1,
                 "绘制期间切换应用，即使没有更多拖动事件也取消")

drawReliability()
pendingLookup?(fixtureGestureTarget)
let executingID = reliabilityMonitor.currentStrokeID
reliabilityMonitor.beginExecution(targetPID: NSRunningApplication.current.processIdentifier)
workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil,
                            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
checkReliability(reliabilityMonitor.currentStrokeID == executingID, "主动激活目标应用不会取消自身动作")
workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
checkReliability(reliabilityMonitor.currentStrokeID != executingID, "等待聚焦时其他应用激活仍取消操作")

reliabilityPreferences.clearGesture(for: .closeTab)
_ = reliabilityPreferences.bind([.right], to: .showDesktop)
pendingLookup = nil
drawReliability()
checkReliability(pendingLookup == nil && reliabilityRecognized == 3, "全局操作无需查询或聚焦窗口")
reliabilityMonitor.finishExecution(strokeID: reliabilityMonitor.currentStrokeID)
let completedID = reliabilityMonitor.currentStrokeID
workspaceNotifications.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)
checkReliability(reliabilityMonitor.currentStrokeID == completedID, "动作完成后的应用切换不改写已完成会话")
reliabilityMonitor.stop()

// Check foreground changes even if the workspace notification has not arrived yet.
reliabilityPreferences.clearGesture(for: .showDesktop)
_ = reliabilityPreferences.bind([.right], to: .closeTab)
private var raceFrontmost: NSRunningApplication? = .current
private var raceCompletion: ((GestureTarget?) -> Void)?
private var raceRecognized = 0
private let raceMonitor = GestureMonitor(preferences: reliabilityPreferences, frontmostApplication: { raceFrontmost },
    captureTarget: { _ in reliabilityRequest }, lookupTarget: { _, completion in raceCompletion = completion; return nil },
    workspaceNotifications: gestureTestNotifications)
raceMonitor.onRecognized = { _, _ in raceRecognized += 1 }
for _ in 0..<2 {
    raceFrontmost = .current
    _ = raceMonitor.sendTrailEvent(.rightMouseDown, x: 100)
    _ = raceMonitor.sendTrailEvent(.rightMouseDragged, x: 220)
    _ = raceMonitor.sendTrailEvent(.rightMouseUp, x: 220)
    drainTrailQueue()
    if raceRecognized == 0 { raceFrontmost = nil }
    raceCompletion?(fixtureGestureTarget)
    checkReliability(raceRecognized == 0, "前台变化但通知未到达时，查询完成也不会执行旧动作")
}
raceFrontmost = .current
_ = raceMonitor.sendTrailEvent(.rightMouseDown, x: 100)
raceFrontmost = nil
checkReliability(!raceMonitor.beginExecution(targetPID: fixtureGestureTarget.pid),
                 "实际执行前复核前台应用，避免排队阶段的切换漏检")
raceMonitor.stop()

// Metadata selection ignores trail panels and preserves topmost window identity.
private func snapshotFixture(_ number: UInt32, pid: Int32 = 100, layer: Int = 0,
                             x: CGFloat = 0, alpha: Double = 1) -> [String: Any] {
    [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: pid,
     kCGWindowLayer as String: layer, kCGWindowAlpha as String: alpha,
     kCGWindowBounds as String: CGRect(x: x, y: 0, width: 500, height: 500).dictionaryRepresentation]
}
let snapshotPoint = CGPoint(x: 100, y: 100)
private let originalSnapshot = WindowSnapshot.at(snapshotPoint, in: [snapshotFixture(1), snapshotFixture(2)])
checkReliability(originalSnapshot?.number == 1, "窗口快照选中起点最上层窗口")
private let withOverlay = WindowSnapshot.at(snapshotPoint, in: [
    snapshotFixture(3, layer: Int(CGWindowLevelForKey(.statusWindow))), snapshotFixture(4, alpha: 0), snapshotFixture(1)
])
checkReliability(withOverlay == originalSnapshot, "轨迹浮层和透明窗口不替换起点目标")
checkReliability(WindowSnapshot.at(snapshotPoint, in: [snapshotFixture(2)]) != originalSnapshot,
                 "相同应用、相同位置的新窗口不冒充原窗口")
checkReliability(WindowSnapshot.at(snapshotPoint, in: [snapshotFixture(1, x: 10)]) != originalSnapshot,
                 "原窗口发生移动时不把鼠标下的新内容视为原始目标")
checkReliability(WindowSnapshot.at(snapshotPoint, in: [snapshotFixture(1, x: 600)]) == nil,
                 "屏幕其他位置的窗口不会成为起点窗口")

// Exercise the production worker, including a slow accessibility server.
private var lookupUsedBackgroundThread = false
private let slowRequest = GestureTargetRequest(pid: fixtureGestureTarget.pid, resolve: {
    lookupUsedBackgroundThread = !Thread.isMainThread
    Thread.sleep(forTimeInterval: 0.3)
    return fixtureGestureTarget
})
private var workerFinished = false
private let lookupStart = ProcessInfo.processInfo.systemUptime
let slowWork = GestureTargetRequest.lookup(slowRequest) { target in
    checkReliability(Thread.isMainThread && target?.pid == fixtureGestureTarget.pid, "查询结果回到主线程")
    workerFinished = true
}
checkReliability(ProcessInfo.processInfo.systemUptime - lookupStart < 0.15, "慢窗口查询不会同步阻塞调用方")
private let workerDeadline = Date().addingTimeInterval(3)
while !workerFinished && Date() < workerDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
}
checkReliability(workerFinished && lookupUsedBackgroundThread, "慢窗口查询在后台正常完成")

extension GestureTarget {
    @MainActor
    fileprivate static func checkFocusWaiting() async {
        var waits = 0
        let late = await waitForFocus(while: { true }, isAvailable: { true },
                                     isFocused: { waits == 12 }, pause: { waits += 1 })
        checkReliability(late && waits == 12, "激活超过原等待窗口仍可成功")
        waits = 0
        let final = await waitForFocus(while: { true }, isAvailable: { true },
                                      isFocused: { waits == 20 }, pause: { waits += 1 })
        checkReliability(final, "最后一次等待之后仍检查焦点")
        waits = 0
        let timeout = await waitForFocus(while: { true }, isAvailable: { true },
                                        isFocused: { false }, pause: { waits += 1 })
        checkReliability(!timeout && waits == 20, "无法聚焦时有界退出")
        waits = 0
        let cancelled = await waitForFocus(while: { waits == 0 }, isAvailable: { true },
                                          isFocused: { waits > 0 }, pause: { waits += 1 })
        checkReliability(!cancelled && waits == 1, "等待中取消不发送到后来聚焦的窗口")
        let unavailable = await waitForFocus(while: { true }, isAvailable: { false }, isFocused: { true })
        checkReliability(!unavailable, "目标失效时不因焦点匹配而执行")
        waits = 0
        let ready = await waitForFocus(while: { true }, isAvailable: { true },
                                      isFocused: { true }, pause: { waits += 1 })
        checkReliability(ready && waits == 0, "已聚焦时不增加固定等待")
    }
}
private var reliabilityAsyncFinished = false
Task { @MainActor in
    for action in GestureAction.available where !action.requiresTargetWindow {
        var sent = false
        _ = await ActionExecutor.execute(action, preferences: reliabilityPreferences,
            target: GestureTarget(pid: fixtureGestureTarget.pid, window: nil), isCurrent: { true },
            permissionCheck: { true }, sendShortcut: { _, _, pid in
                sent = pid == nil
                return "mock"
            })
        checkReliability(sent, "系统操作 \(action.rawValue) 无窗口也能发送且不聚焦应用")
    }
    checkReliability(GestureAction.emoji.requiresTargetWindow && GestureAction.appWindows.requiresTargetWindow,
                     "依赖输入焦点或指定应用的功能保留目标校验")
    await GestureTarget.checkFocusWaiting()
    reliabilityAsyncFinished = true
}
private let reliabilityDeadline = Date().addingTimeInterval(3)
while !reliabilityAsyncFinished && Date() < reliabilityDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
}
checkReliability(reliabilityAsyncFinished, "异步执行回归完成")
print("手势可靠性测试通过：\(reliabilityChecks) 项")
