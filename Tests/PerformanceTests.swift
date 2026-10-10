// Behavioral performance regressions: isolated preferences, no system event taps.
private var performanceChecks = 0
private func checkPerformance(_ condition: @autoclosure () -> Bool, _ message: String) {
    performanceChecks += 1
    if !condition() { fatalError(message) }
}
private let performanceSuite = "MouseGesture.PerformanceTests.\(UUID().uuidString)"
private let performanceDefaults = UserDefaults(suiteName: performanceSuite)!
defer { performanceDefaults.removePersistentDomain(forName: performanceSuite) }
private let performancePreferences = Preferences(defaults: performanceDefaults)
private let performanceState = AppState(preferences: performancePreferences, usesSystemShortcutCapture: false,
                                        permissionCheck: { false })
performanceState.addCustomDraft()
private let firstDraft = performanceState.draftModels[0]
private let secondDraft = performanceState.draftModels[1]
private var formUpdates = 0
private var firstUpdates = 0
private var secondUpdates = 0
private var preferenceUpdates = 0
private var performanceSubscriptions: Set<AnyCancellable> = []
performanceState.objectWillChange.sink { formUpdates += 1 }.store(in: &performanceSubscriptions)
firstDraft.objectWillChange.sink { firstUpdates += 1 }.store(in: &performanceSubscriptions)
secondDraft.objectWillChange.sink { secondUpdates += 1 }.store(in: &performanceSubscriptions)
performancePreferences.objectWillChange.sink { preferenceUpdates += 1 }.store(in: &performanceSubscriptions)
private let originalStoredPreferences = performanceDefaults.data(forKey: "preferences.v1")
for index in 0..<100 {
    firstDraft.value.name = "自定义名称 \(index)"
}
checkPerformance(firstUpdates == 100, "每次输入立即更新当前行，不用防抖延迟输入")
checkPerformance(formUpdates == 0 && secondUpdates == 0, "连续输入不会刷新整页或其他草稿行")
checkPerformance(preferenceUpdates == 0 && performanceDefaults.data(forKey: "preferences.v1") == originalStoredPreferences,
                 "输入名称不写入已保存配置")
performanceState.activateCustomDraft(firstDraft.id)
formUpdates = 0
performanceState.customDraft?.name = "修改后的名称"
performanceState.customDraft?.shortcut = .init(keyCode: 7, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘ X")
performanceState.customDraft?.directions = [.right, .down]
checkPerformance(formUpdates == 0 && firstDraft.value.name == "修改后的名称", "活动草稿与当前行共享内容，更新不通知整页")
checkPerformance(performanceState.draftModels[0] === firstDraft, "编辑和快捷键录入保持行身份与焦点")
checkPerformance(performancePreferences.saveCustomAction(firstDraft.value) == nil, "立即保存读取最新输入、快捷键和手势")
checkPerformance(Preferences(defaults: performanceDefaults).customActions.first?.name == "修改后的名称", "保存后完整持久化最新名称")
performanceState.removeCustomDraft(firstDraft.id)
checkPerformance(performanceState.draftModels.first === secondDraft, "移除已保存行不重建其他草稿")
performanceState.stop()

extension AppState {
    fileprivate func testPowerLifecycle() {
        preferences.enabled = false
        start()
        checkPerformance(timer == nil && !monitor.isRunning && !running, "暂停状态启动不安装监听或启动权限定时器")
        preferences.enabled = true
        checkPerformance(timer?.timeInterval == 2, "等待授权时每两秒自动重试")
        editCustomAction()
        customDraft?.name = "未授权时仍可编辑"
        refreshPermission()
        checkPerformance(customDraft?.name == "未授权时仍可编辑", "权限轮询不会打断本地草稿编辑")
        stopRecording()
        let retryTimer = timer
        start()
        refreshPermission()
        checkPerformance(timer === retryTimer, "重复启动和检查不会重复注册或重建定时器")
        updatePermissionTimer(listening: true, enabled: true)
        checkPerformance(timer?.timeInterval == 30 && timer?.tolerance == 5, "正常监听时减少检查频率并允许系统合并唤醒")
        let healthyTimer = timer
        updatePermissionTimer(listening: true, enabled: true)
        checkPerformance(timer === healthyTimer, "稳定运行沿用同一定时器")
        preferences.enabled = false
        checkPerformance(timer == nil && healthyTimer?.isValid == false && !monitor.isRunning,
                         "暂停立即移除监听并停止定时唤醒")
        preferences.enabled = true
        let beforeSleep = timer
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.post(name: NSWorkspace.willSleepNotification, object: nil)
        checkPerformance(sleeping && timer == nil && beforeSleep?.isValid == false && !monitor.isRunning,
                         "休眠停止轮询和监听")
        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        checkPerformance(timer == nil, "仅唤醒但会话未激活时保持停止")
        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        checkPerformance(timer?.timeInterval == 2, "会话恢复后重新检测权限")
        let resumedTimer = timer
        stop()
        checkPerformance(timer == nil && resumedTimer?.isValid == false && !running, "退出后无定时器或监听残留")
        workspace.post(name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        preferences.enabled = false
        preferences.enabled = true
        checkPerformance(timer == nil && !monitor.isRunning, "退出后通知和偏好变化不会重新启动监听")
    }
}
private let powerState = AppState(preferences: performancePreferences, usesSystemShortcutCapture: false,
                                  permissionCheck: { false })
powerState.testPowerLifecycle()
print("输入更新范围与节能生命周期测试通过：\(performanceChecks) 项（100 次输入，整页更新 0 次）")
