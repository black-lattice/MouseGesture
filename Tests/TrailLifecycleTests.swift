// check.sh concatenates these tests with the sources so private lifecycle state can
// be checked without exposing test hooks. No event tap or system shortcut is sent.
private let gestureTestNotifications = NotificationCenter()
private let fixtureGestureTarget = GestureTarget(pid: NSRunningApplication.current.processIdentifier,
                                                 window: AXUIElementCreateApplication(NSRunningApplication.current.processIdentifier))
private func fixtureRequest(_ target: GestureTarget) -> GestureTargetRequest {
    GestureTargetRequest(pid: target.pid, resolve: { target })
}
private func fixtureLookup(_ request: GestureTargetRequest, completion: @escaping (GestureTarget?) -> Void) -> DispatchWorkItem? {
    completion(request.resolve())
    return nil
}
private var trailChecks = 0
private var trailFailures: [String] = []
private func expectTrail(_ condition: @autoclosure () -> Bool, _ name: String) {
    trailChecks += 1
    if !condition() { trailFailures.append(name) }
}

private func drainTrailQueue() {
    var finished = false
    DispatchQueue.main.async { finished = true }
    let deadline = Date().addingTimeInterval(2)
    while !finished && Date() < deadline {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005))
    }
    expectTrail(finished, "异步轨迹任务完成")
}

extension TrailOverlay {
    fileprivate func prepareOffscreenForTest() {
        prepare()
        panels.forEach { $0.setFrameOrigin(CGPoint(x: -100_000, y: -100_000)) }
    }

    fileprivate var pointCountsForTest: [Int] { views.map { $0.points.count } }
    fileprivate var isEmptyForTest: Bool { panels.isEmpty && views.isEmpty }
    fileprivate var hasNoDrawingForTest: Bool { views.allSatisfy { $0.points.isEmpty } }
    fileprivate var isHiddenForTest: Bool { panels.allSatisfy { !$0.isVisible } && hasNoDrawingForTest }
    fileprivate var hasNoLabelForTest: Bool { views.allSatisfy { $0.resultLabelForTest.isEmpty } }

    fileprivate func testImmediateHide() {
        prepareOffscreenForTest()
        expectTrail(!panels.isEmpty, "为显示器创建测试浮层")
        expectTrail(panels.allSatisfy { $0.animationBehavior == .none }, "轨迹浮层禁用自动窗口动画")
        show(points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10)], label: "测试")
        expectTrail(panels.allSatisfy { !$0.isVisible }, "没有轨迹经过的显示器不显示浮层")
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let origin = panels[0].frame.origin
        show(points: [CGPoint(x: origin.x + 10, y: primaryTop - origin.y - 100),
                      CGPoint(x: origin.x + 110, y: primaryTop - origin.y - 100)], label: "测试")
        let displayedPanels = panels
        expectTrail(displayedPanels.allSatisfy(\.isVisible), "轨迹绘制时显示浮层（测试窗口位于屏幕外）")
        expectTrail(views.allSatisfy { !$0.needsDisplay }, "首次显示浮层时首帧内容已完成绘制")
        hide()
        expectTrail(displayedPanels.allSatisfy { !$0.isVisible && $0.alphaValue == 0 }, "隐藏立即移除浮层可见内容")
        expectTrail(isEmptyForTest, "隐藏后释放全部显示器轨迹")

    }
}

extension TrailView {
    fileprivate var resultLabelForTest: String { label }
}

extension GestureMonitor {
    fileprivate func sendTrailEvent(_ type: CGEventType, x: CGFloat) -> Bool {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: CGPoint(x: x, y: 100), mouseButton: .right)!
        event.flags = []
        return handle(type: type, event: event) == nil
    }

    fileprivate func testTrailLifecycle() {
        var recognized: [[Direction]] = []
        onRecognized = { [weak self] directions, _ in
            expectTrail(self?.overlay.isHiddenForTest == true, "执行桌面动作前已清除轨迹并隐藏浮层")
            recognized.append(directions)
        }

        // A delayed drawing block from a cancelled stroke cannot paint a new one.
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        cancel()
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        overlay.prepareOffscreenForTest()
        drainTrailQueue()
        expectTrail(overlay.hasNoDrawingForTest, "下一笔开始后不会重绘上一笔残留轨迹")
        cancel()

        // External Space changes cancel drawing even when the frontmost PID is unchanged.
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        gestureTestNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        expectTrail(stroke == nil && swallowUntilUp, "桌面变化立即取消进行中的手势")
        drainTrailQueue()
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        expectTrail(overlay.isEmptyForTest && previewTimer == nil, "桌面变化取消绘制和停顿提示任务")
        expectTrail(sendTrailEvent(.rightMouseUp, x: 220) && !swallowUntilUp, "取消后吞掉右键松开且恢复后续操作")
        expectTrail(recognized.isEmpty, "切换桌面取消的手势不会执行动作")

        // Normal completion still clears the trail before calling the action executor.
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        overlay.prepareOffscreenForTest()
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        drainTrailQueue()
        expectTrail(!overlay.hasNoDrawingForTest, "有效手势仍然正常绘制")
        expectTrail(overlay.hasNoLabelForTest, "绘制过程中不显示匹配文字")
        let idleTimer = previewTimer
        let idleDeadline = idleTimer?.fireDate
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        expectTrail(overlay.hasNoLabelForTest, "停顿不足 200ms 不显示提示")
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        expectTrail(previewTimer === idleTimer && previewTimer?.fireDate == idleDeadline,
                    "重复位置事件不延后停顿提示")
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        expectTrail(!overlay.hasNoLabelForTest && overlay.pointCountsForTest.allSatisfy { $0 > 1 },
                    "仍按住右键时，停顿约 200ms 后显示提示并保留轨迹")
        expectTrail(recognized.isEmpty && previewTimer == nil, "停顿只预览一次，不执行动作或持续匹配")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        expectTrail(!overlay.hasNoLabelForTest, "保持静止时提示继续显示")
        for x: CGFloat in [221, 219, 220.5, 219.5, 222] {
            _ = sendTrailEvent(.rightMouseDragged, x: x)
        }
        drainTrailQueue()
        expectTrail(!overlay.hasNoLabelForTest && previewTimer == nil,
                    "提示出现后小范围抖动不会反复隐藏并重启提示")
        _ = sendTrailEvent(.rightMouseDragged, x: 223)
        drainTrailQueue()
        expectTrail(overlay.hasNoLabelForTest && previewTimer != nil,
                    "累积移动达到 3 点时隐藏提示，即使每次事件移动很小")
        let resumedTimer = previewTimer
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        _ = sendTrailEvent(.rightMouseDragged, x: 260)
        expectTrail(previewTimer === resumedTimer, "连续移动复用同一定时器")
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        expectTrail(overlay.hasNoLabelForTest, "连续移动重新计算停顿时间，旧截止时间不弹提示")
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        expectTrail(!overlay.hasNoLabelForTest, "再次停顿后显示新的匹配提示")
        _ = sendTrailEvent(.rightMouseUp, x: 260)
        drainTrailQueue()
        expectTrail(recognized == [[.right]], "正常松开只执行一次识别动作")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        expectTrail(overlay.isEmptyForTest && previewTimer == nil, "松开后清除提示，延迟任务不会重新显示")

        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        trailPhysicalButtonPressed = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        expectTrail(overlay.hasNoLabelForTest && recognized.count == 1,
                    "物理右键已松开但松开事件尚未处理时不显示提示或提前执行")
        _ = sendTrailEvent(.rightMouseUp, x: 220)
        drainTrailQueue()
        expectTrail(recognized.count == 2, "松开事件到达后立即执行识别动作")
        trailPhysicalButtonPressed = true

        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        _ = sendTrailEvent(.rightMouseUp, x: 220)
        gestureTestNotifications.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        drainTrailQueue()
        expectTrail(recognized.count == 2 && overlay.isEmptyForTest, "桌面变化也取消已排队但尚未执行的动作")
        // A busy event stream keeps one queued draw and paints the newest points.
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        overlay.prepareOffscreenForTest()
        for index in 1...100 {
            lastDraw = 0 // Emulate events spanning multiple display frames without running the queue.
            _ = sendTrailEvent(.rightMouseDragged, x: 100 + CGFloat(index) * 4)
        }
        expectTrail(drawPending, "高频拖动只保留等待绘制状态")
        let latestPointCount = stroke?.points.count
        drainTrailQueue()
        expectTrail(!drawPending && overlay.pointCountsForTest.allSatisfy { $0 == latestPointCount },
                    "排队绘制使用最新完整轨迹，完成后释放等待状态")
        for _ in 0..<100 {
            lastDraw = 0
            _ = sendTrailEvent(.rightMouseDragged, x: 500)
        }
        expectTrail(!drawPending, "100 次重复位置事件不再排队识别或绘制")
        preferences.minimumLength = 60
        lastDraw = 0
        _ = sendTrailEvent(.rightMouseDragged, x: 500)
        expectTrail(!drawPending, "识别阈值变化不触发拖动中的匹配或文字刷新")
        drainTrailQueue()
        lastDraw = 0
        _ = sendTrailEvent(.rightMouseDragged, x: 600)
        preferences.showTrail = false
        overlay.hide()
        drainTrailQueue()
        expectTrail(overlay.isEmptyForTest, "关闭轨迹后旧绘制任务不会重新显示浮层")
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        expectTrail(stroke != nil && previewTimer == nil && overlay.isEmptyForTest,
                    "停顿等待期间关闭显示只隐藏预览，不取消仍在进行的手势")
        _ = sendTrailEvent(.rightMouseUp, x: 600)
        drainTrailQueue()
        expectTrail(overlay.isEmptyForTest, "关闭显示选项后，松开也不显示提示")
        preferences.showTrail = true
        cancel()

        let callback = onRecognized
        onRecognized = { [weak self] directions, pid in
            callback?(directions, pid)
            self?.cancel()
        }
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        _ = sendTrailEvent(.rightMouseUp, x: 220)
        drainTrailQueue()
        expectTrail(overlay.isEmptyForTest, "动作执行期间被取消时，不重新弹出停顿提示")
        onRecognized = callback
        stop()
    }
}

let trailSuite = "MouseGesture.TrailTests.\(UUID().uuidString)"
let trailDefaults = UserDefaults(suiteName: trailSuite)!
defer { trailDefaults.removePersistentDomain(forName: trailSuite) }
let trailPreferences = Preferences(defaults: trailDefaults)
trailPreferences.enabled = true
trailPreferences.showTrail = true
TrailOverlay().testImmediateHide()
// CI may have no foreground app. Keep the fixture independent of the runner's desktop.
private var trailPhysicalButtonPressed = true
GestureMonitor(preferences: trailPreferences, frontmostApplication: { .current },
               rightButtonPressed: { trailPhysicalButtonPressed },
               captureTarget: { _ in fixtureRequest(fixtureGestureTarget) }, lookupTarget: fixtureLookup, workspaceNotifications: gestureTestNotifications).testTrailLifecycle()
if trailFailures.isEmpty { print("轨迹浮层生命周期测试通过：\(trailChecks) 项") }
else { trailFailures.forEach { print("失败：\($0)") }; exit(1) }
