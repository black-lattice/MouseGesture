import AppKit

extension AppState {
    func recordMouseShortcut(_ button: MouseButton) {
        stopRecording()
        recordingMouseShortcut = button
        monitor.suspended = true
        monitor.cancel()
        let started = shortcutRecorder.start(onInterrupted: { [weak self] in self?.shortcutRecordingInterrupted() }) { [weak self] event in
            guard let self else { return }
            if KeyboardShortcut.isCancel(event) { self.stopRecording(); return }
            guard let shortcut = KeyboardShortcut.recorded(from: event) else {
                self.mouseRecordingError = "请使用带修饰键的组合，或方向键 / F1–F20。"
                return
            }
            self.preferences.setMouseShortcut(shortcut, for: button)
            self.stopRecording()
            self.lastResult = "已绑定：\(button.title) → \(shortcut.label)"
        }
        if !started { shortcutRecordingFailed() }
    }

    func recordMouseButton(_ button: MouseButton) {
        stopRecording()
        recordingMouseButton = button
        monitor.suspended = true
        monitor.cancel()
        var pressed = Set<Int>()
        var candidate: Int?
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .otherMouseUp, .otherMouseDragged, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if KeyboardShortcut.isCancel(event) { self.stopRecording(); return nil }
                return event
            }
            guard (2...31).contains(event.buttonNumber) else { return event }
            if event.type == .otherMouseDown {
                pressed.insert(event.buttonNumber)
                if candidate == nil { candidate = event.buttonNumber }
                return nil
            }
            guard pressed.contains(event.buttonNumber) else { return event }
            if event.type == .otherMouseUp {
                pressed.remove(event.buttonNumber)
                if pressed.isEmpty, let candidate {
                    self.preferences.setMouseButtonNumber(Int64(candidate), for: button)
                    self.stopRecording()
                    self.lastResult = "已识别\(button.title)，可继续录入快捷键"
                }
            }
            return nil
        }
    }
}
