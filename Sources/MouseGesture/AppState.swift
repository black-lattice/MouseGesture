import AppKit
import ApplicationServices
import Combine

final class AppState: ObservableObject {
    let preferences: Preferences
    lazy var monitor = GestureMonitor(preferences: preferences)
    @Published var trusted: Bool
    @Published var running = false
    @Published var lastResult = "按住右键绘制，松开执行操作"
    @Published var gestureRecordingAction: GestureAction?
    @Published private(set) var draftModels: [CustomActionDraftModel] = []
    var customDrafts: [CustomActionDraft] {
        get { draftModels.map(\.value) }
        set {
            let existing = Dictionary(uniqueKeysWithValues: draftModels.map { ($0.id, $0) })
            let models = newValue.map { value -> CustomActionDraftModel in
                guard let model = existing[value.id] else { return CustomActionDraftModel(value) }
                if model.value != value { model.value = value }
                return model
            }
            if models.map(\.id) != draftModels.map(\.id) { draftModels = models }
        }
    }
    @Published private var activeCustomDraftID: UUID?
    var customDraft: CustomActionDraft? {
        get { draftModels.first { $0.id == activeCustomDraftID }?.value }
        set {
            if let draft = newValue {
                if let model = draftModels.first(where: { $0.id == draft.id }) {
                    if model.value != draft { model.value = draft }
                } else { draftModels.append(CustomActionDraftModel(draft)) }
            }
            if activeCustomDraftID != newValue?.id { activeCustomDraftID = newValue?.id }
        }
    }
    @Published var recordingCustomShortcut = false
    @Published var recordingMouseShortcut: MouseButton?
    @Published var recordingMouseButton: MouseButton?
    @Published var mouseRecordingError: String?
    private var timer: Timer?
    private var enabledSubscription: AnyCancellable?
    private var hasStarted = false
    private var sleeping = false
    private var sessionActive = true
    var keyboardMonitor: Any?
    let shortcutRecorder: ShortcutRecorder
    private let permissionCheck: () -> Bool

    init(preferences: Preferences = Preferences(), usesSystemShortcutCapture: Bool = true,
         permissionCheck: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.preferences = preferences
        self.permissionCheck = permissionCheck
        trusted = permissionCheck()
        shortcutRecorder = ShortcutRecorder(usesSystemCapture: usesSystemShortcutCapture)
        ensureCustomDraft()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        monitor.onStatus = { [weak self] in self?.lastResult = $0 }
        monitor.mouseButtons.onClick = { [weak self] button, shortcut, pid in
            self?.lastResult = ActionExecutor.send(shortcut, title: button.title, targetPID: pid)
        }
        monitor.onRecognized = { [weak self] directions, target in
            guard let self, self.preferences.enabled,
                  self.gestureRecordingAction == nil, self.customDraft == nil else { return }
            let strokeID = self.monitor.currentStrokeID
            let isCurrent = { [weak self] in
                guard let self else { return false }
                return self.monitor.currentStrokeID == strokeID && self.preferences.enabled
                    && !self.monitor.suspended && !self.preferences.excludes(target.bundleIdentifier)
            }
            Task { @MainActor [weak self] in
                guard let self, isCurrent() else { return }
                let needsWindow = self.preferences.customAction(for: directions, bundleID: target.bundleIdentifier) != nil
                    || self.preferences.action(for: directions, bundleID: target.bundleIdentifier).requiresTargetWindow
                guard self.monitor.beginExecution(targetPID: needsWindow ? target.pid : nil) else { return }
                defer { self.monitor.finishExecution(strokeID: strokeID) }
                let result: String
                if let custom = self.preferences.customAction(for: directions, bundleID: target.bundleIdentifier) {
                    result = await ActionExecutor.execute(custom, target: target, isCurrent: isCurrent)
                } else {
                    result = await ActionExecutor.execute(self.preferences.action(for: directions, bundleID: target.bundleIdentifier),
                                                          preferences: self.preferences, target: target,
                                                          isCurrent: isCurrent)
                }
                if isCurrent() { self.lastResult = result }
            }
        }
        refreshPermission()
        enabledSubscription = preferences.$enabled.dropFirst().removeDuplicates().sink { [weak self] enabled in
            self?.refreshPermission(enabled: enabled)
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resume),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(resume),
                                                          name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(applicationActivated),
                                               name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func suspend(_ notification: Notification) {
        if notification.name == NSWorkspace.willSleepNotification { sleeping = true }
        if notification.name == NSWorkspace.sessionDidResignActiveNotification { sessionActive = false }
        timer?.invalidate()
        timer = nil
        stopRecording()
        monitor.stop()
        if running { running = false }
    }

    @objc private func resume(_ notification: Notification) {
        if notification.name == NSWorkspace.didWakeNotification { sleeping = false }
        if notification.name == NSWorkspace.sessionDidBecomeActiveNotification { sessionActive = true }
        refreshPermission()
    }

    @objc private func applicationActivated() { refreshPermission() }

    func refreshPermission(enabled: Bool? = nil) {
        let permission = permissionCheck()
        if trusted != permission { trusted = permission }
        let listening: Bool
        let shouldListen = (enabled ?? preferences.enabled) && !sleeping && sessionActive
        if permission && shouldListen {
            listening = monitor.start()
        } else {
            monitor.stop()
            listening = false
        }
        if running != listening { running = listening }
        updatePermissionTimer(listening: permission && listening, enabled: shouldListen)
    }

    private func updatePermissionTimer(listening: Bool, enabled: Bool) {
        // Retry grants promptly; a healthy listener needs only an occasional permission check.
        let interval: TimeInterval? = hasStarted && enabled ? (listening ? 30 : 2) : nil
        if timer?.timeInterval != interval {
            timer?.invalidate()
            timer = interval.map { seconds in
                let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
                    self?.refreshPermission()
                }
                timer.tolerance = seconds == 30 ? 5 : 0.5
                return timer
            }
        }
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSettings("Privacy_Accessibility")
    }

    func openSettings(_ section: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(section)") {
            NSWorkspace.shared.open(url)
        }
    }

    func recordGesture(_ action: GestureAction) {
        stopRecording()
        gestureRecordingAction = action
        monitor.suspended = true
        monitor.cancel()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.stopRecording(); return nil }
            return event
        }
    }

    func editCustomAction(_ action: CustomAction? = nil) {
        let draft = action.flatMap { action in customDrafts.first { $0.id == action.id } } ?? CustomActionDraft(action: action)
        stopRecording()
        customDraft = draft
        monitor.suspended = true
        monitor.cancel()
    }

    func addCustomDraft() {
        stopRecording()
        customDrafts.append(CustomActionDraft())
    }

    func activateCustomDraft(_ id: UUID) {
        guard let draft = customDrafts.first(where: { $0.id == id }) else { return }
        stopRecording()
        customDraft = draft
        monitor.suspended = true
        monitor.cancel()
    }

    func removeCustomDraft(_ id: UUID) {
        if customDraft?.id == id { stopRecording() }
        customDrafts.removeAll { $0.id == id }
        ensureCustomDraft()
    }

    func ensureCustomDraft() {
        if customDrafts.isEmpty && preferences.customActions.isEmpty { customDrafts.append(CustomActionDraft()) }
    }

    func resetCustomDrafts() {
        stopRecording()
        customDrafts = []
        ensureCustomDraft()
    }

    func recordCustomShortcut() {
        guard customDraft != nil else { return }
        stopCustomShortcutRecording()
        recordingCustomShortcut = true
        customDraft?.shortcutError = nil
        let started = shortcutRecorder.start(onInterrupted: { [weak self] in self?.shortcutRecordingInterrupted() }) { [weak self] event in
            guard let self else { return }
            if KeyboardShortcut.isCancel(event) { self.stopCustomShortcutRecording(); return }
            guard let shortcut = KeyboardShortcut.recorded(from: event) else {
                self.customDraft?.shortcutError = "请使用带修饰键的组合，或方向键 / F1–F20。"
                return
            }
            self.customDraft?.shortcut = shortcut
            self.customDraft?.shortcutError = nil
            self.stopCustomShortcutRecording()
        }
        if !started { shortcutRecordingFailed() }
    }

    func shortcutRecordingInterrupted() {
        stopRecording()
        lastResult = "快捷键录制已中断，请重新点击录制。"
    }

    func shortcutRecordingFailed() {
        let message = "无法拦截快捷键，请检查辅助功能权限后重新录制；若系统要求输入监控权限，也请开启。"
        customDraft?.shortcutError = message
        stopRecording()
        lastResult = message
    }

    func stopCustomShortcutRecording() {
        shortcutRecorder.stop()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        recordingCustomShortcut = false
    }

    func stopRecording() {
        shortcutRecorder.stop()
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        if gestureRecordingAction != nil { gestureRecordingAction = nil }
        customDraft = nil
        if recordingCustomShortcut { recordingCustomShortcut = false }
        if recordingMouseShortcut != nil { recordingMouseShortcut = nil }
        if recordingMouseButton != nil { recordingMouseButton = nil }
        if mouseRecordingError != nil { mouseRecordingError = nil }
        monitor.suspended = false
    }

    func stop() {
        hasStarted = false
        timer?.invalidate()
        timer = nil
        enabledSubscription = nil
        stopRecording()
        monitor.stop()
        if running { running = false }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }
}
