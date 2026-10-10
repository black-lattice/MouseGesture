// check.sh concatenates these tests with the sources so private lifecycle state can
// be checked without exposing test hooks. No event tap or system shortcut is sent.
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

    fileprivate func testImmediateHide() {
        prepareOffscreenForTest()
        expectTrail(!panels.isEmpty, "为显示器创建测试浮层")
        expectTrail(panels.allSatisfy { $0.animationBehavior == .none }, "轨迹浮层禁用自动窗口动画")
        show(points: [CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 10)], label: "测试")
        let displayedPanels = panels
        expectTrail(displayedPanels.allSatisfy(\.isVisible), "轨迹绘制时显示浮层（测试窗口位于屏幕外）")
        hide()
        expectTrail(displayedPanels.allSatisfy { !$0.isVisible && $0.alphaValue == 0 }, "隐藏立即移除浮层可见内容")
        expectTrail(isEmptyForTest, "隐藏后释放全部显示器轨迹")
    }
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
            expectTrail(self?.overlay.isEmptyForTest == true, "执行桌面动作前已清除浮层")
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
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        expectTrail(stroke == nil && swallowUntilUp, "桌面变化立即取消进行中的手势")
        drainTrailQueue()
        expectTrail(overlay.isEmptyForTest, "桌面变化后排队的绘制不会恢复浮层")
        expectTrail(sendTrailEvent(.rightMouseUp, x: 220) && !swallowUntilUp, "取消后吞掉右键松开且恢复后续操作")
        expectTrail(recognized.isEmpty, "切换桌面取消的手势不会执行动作")

        // Normal completion still clears the trail before calling the action executor.
        _ = sendTrailEvent(.rightMouseDown, x: 100)
        overlay.prepareOffscreenForTest()
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        drainTrailQueue()
        expectTrail(!overlay.hasNoDrawingForTest, "有效手势仍然正常绘制")
        _ = sendTrailEvent(.rightMouseUp, x: 220)
        drainTrailQueue()
        expectTrail(recognized == [[.right]], "正常松开只执行一次识别动作")

        _ = sendTrailEvent(.rightMouseDown, x: 100)
        _ = sendTrailEvent(.rightMouseDragged, x: 220)
        _ = sendTrailEvent(.rightMouseUp, x: 220)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        drainTrailQueue()
        expectTrail(recognized.count == 1 && overlay.isEmptyForTest, "桌面变化也取消已排队但尚未执行的动作")
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
        lastDraw = 0
        _ = sendTrailEvent(.rightMouseDragged, x: 600)
        preferences.showTrail = false
        overlay.hide()
        drainTrailQueue()
        expectTrail(overlay.isEmptyForTest, "关闭轨迹后旧绘制任务不会重新显示浮层")
        preferences.showTrail = true
        cancel()
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
GestureMonitor(preferences: trailPreferences, frontmostApplication: { .current }).testTrailLifecycle()
if trailFailures.isEmpty { print("轨迹浮层生命周期测试通过：\(trailChecks) 项") }
else { trailFailures.forEach { print("失败：\($0)") }; exit(1) }
