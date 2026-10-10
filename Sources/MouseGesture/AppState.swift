import AppKit
import ApplicationServices
import Combine

final class AppState: ObservableObject {
    let preferences = Preferences()
    lazy var monitor = GestureMonitor(preferences: preferences)
    @Published var trusted = AXIsProcessTrusted()
    @Published var running = false
    @Published var lastResult = "按住右键绘制，松开执行操作"
    @Published var recordingAction: GestureAction?
    private var timer: Timer?
    private var keyboardMonitor: Any?

    func start() {
        monitor.onStatus = { [weak self] in self?.lastResult = $0 }
        monitor.onRecognized = { [weak self] directions, pid in
            guard let self, self.preferences.enabled, self.recordingAction == nil else { return }
            self.lastResult = ActionExecutor.execute(self.preferences.action(for: directions),
                                                    preferences: self.preferences, targetPID: pid)
        }
        refreshPermission()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermission() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(suspend),
                                                          name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
    }

    @objc private func suspend() { monitor.cancel() }

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

    func record(_ action: GestureAction) {
        stopRecording()
        recordingAction = action
        monitor.suspended = true
        monitor.cancel()
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { self.stopRecording(); return nil }
            let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
            let special: [UInt16: String] = [123: "←", 124: "→", 125: "↓", 126: "↑", 103: "F11",
                                            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5",
                                            97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 111: "F12"]
            guard !flags.isEmpty || special[event.keyCode] != nil else {
                self.lastResult = "请使用带修饰键的组合，或方向键 / F1–F12"
                return nil
            }
            var symbols = ""
            if flags.contains(.control) { symbols += "⌃ " }
            if flags.contains(.option) { symbols += "⌥ " }
            if flags.contains(.shift) { symbols += "⇧ " }
            if flags.contains(.command) { symbols += "⌘ " }
            let key = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
            self.preferences.shortcuts[action.rawValue] = .init(keyCode: event.keyCode,
                                                               modifiers: UInt64(flags.rawValue), label: symbols + key)
            self.stopRecording()
            return nil
        }
    }

    func stopRecording() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        keyboardMonitor = nil
        recordingAction = nil
        monitor.suspended = false
    }

    func stop() {
        timer?.invalidate()
        stopRecording()
        monitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }
}
