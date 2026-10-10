import AppKit
import ApplicationServices
import Combine

final class AppState: ObservableObject {
    let preferences: Preferences
    lazy var monitor = GestureMonitor(preferences: preferences)
    @Published var trusted = AXIsProcessTrusted()
    @Published var running = false
    @Published var lastResult = "按住右键绘制，松开执行操作"
    @Published var gestureRecordingAction: GestureAction?
    @Published var customDrafts: [CustomActionDraft] = []
    @Published private var activeCustomDraftID: UUID?
    var customDraft: CustomActionDraft? {
        get { customDrafts.first { $0.id == activeCustomDraftID } }
        set {
            if let draft = newValue {
                if let index = customDrafts.firstIndex(where: { $0.id == draft.id }) { customDrafts[index] = draft }
                else { customDrafts.append(draft) }
            }
            activeCustomDraftID = newValue?.id
        }
    }
    @Published var recordingCustomShortcut = false
    private var timer: Timer?
    private var keyboardMonitor: Any?
    private let shortcutRecorder: ShortcutRecorder

    init(preferences: Preferences = Preferences(), usesSystemShortcutCapture: Bool = true) {
        self.preferences = preferences
        shortcutRecorder = ShortcutRecorder(usesSystemCapture: usesSystemShortcutCapture)
        ensureCustomDraft()
    }

    func start() {
        monitor.onStatus = { [weak self] in self?.lastResult = $0 }
        monitor.onRecognized = { [weak self] directions, pid in
            guard let self, self.preferences.enabled,
                  self.gestureRecordingAction == nil, self.customDraft == nil else { return }
            if let custom = self.preferences.customAction(for: directions) {
                self.lastResult = ActionExecutor.execute(custom, targetPID: pid)
            } else {
                self.lastResult = ActionExecutor.execute(self.preferences.action(for: directions),
                                                        preferences: self.preferences, targetPID: pid)
            }
        }
        refreshPermission()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermission() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    @objc private func suspend() { stopRecording(); monitor.cancel() }

    func refreshPermission() {
        let permission = AXIsProcessTrusted()
        if trusted != permission { trusted = permission }
        let listening: Bool
        if permission {
            listening = monitor.start()
        } else {
            monitor.stop()
            listening = false
        }
        if running != listening { running = listening }
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

    private func shortcutRecordingInterrupted() {
        stopRecording()
        lastResult = "快捷键录制已中断，请重新点击录制。"
    }

    private func shortcutRecordingFailed() {
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
        gestureRecordingAction = nil
        customDraft = nil
        recordingCustomShortcut = false
        monitor.suspended = false
    }

    func stop() {
        timer?.invalidate()
        stopRecording()
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
