import SwiftUI

struct MouseButtonSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences

    var body: some View {
        Section {
            ForEach(MouseButton.allCases) { button in
                let binding = preferences.mouseBinding(for: button)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: ActionRowLayout.spacing) {
                        Text(button.title).frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            state.recordMouseShortcut(button)
                        } label: {
                            Text(state.recordingMouseShortcut == button ? "请按快捷键…" : (binding.shortcut?.label ?? "录入快捷键"))
                                .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .frame(width: ActionRowLayout.shortcutWidth)
                        .disabled(state.recordingMouseShortcut == button)
                        .accessibilityLabel("录入\(button.title)快捷键")
                        Button("识别按键") { state.recordMouseButton(button) }
                            .disabled(state.recordingMouseButton == button)
                            .accessibilityLabel("识别鼠标的\(button.title)")
                            .help("当前按键编号：\(binding.buttonNumber)。鼠标侧键不对应时，点击后按一下实际按键。")
                        Button("清除") {
                            state.stopRecording()
                            preferences.setMouseShortcut(nil, for: button)
                        }
                        .disabled(binding.shortcut == nil)
                        .accessibilityLabel("清除\(button.title)快捷键并恢复原功能")
                    }
                    if state.recordingMouseShortcut == button || state.recordingMouseButton == button {
                        HStack {
                            Text(state.recordingMouseButton == button
                                 ? "将指针放在此设置窗口内，按下并松开鼠标的\(button.title)。Esc 取消。"
                                 : "按下要绑定的快捷键，松开保存。Esc 取消。")
                                .font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button("取消") { state.stopRecording() }
                        }
                        if let error = state.mouseRecordingError {
                            Text(error).font(.callout).foregroundStyle(.red)
                        }
                    }
                }
            }
        } header: {
            Text("鼠标按键")
        } footer: {
            Text("录入快捷键后，点击并松开按键执行一次，替代原功能；清除后恢复原功能。拖动不触发。侧键不对应时可重新识别，已占用的按键会互换；鼠标驱动需将按键设为原生鼠标按键。")
        }
    }
}
