import SwiftUI
import ServiceManagement

struct GeneralSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @State private var loginEnabled = false
    @State private var needsApproval = false
    @State private var loginError: String?

    var body: some View {
        Section("启动与手势触发") {
            Toggle("登录时启动", isOn: Binding(get: { loginEnabled }, set: setLoginEnabled))
            if needsApproval {
                Text("请在系统设置中允许 MouseGesture 登录时启动。").foregroundStyle(.secondary)
                Button("打开登录项设置") { SMAppService.openSystemSettingsLoginItems() }
            }
            if let loginError { Text(loginError).foregroundStyle(.red) }
            Picker("按住绘制的鼠标按键", selection: Binding(get: { preferences.triggerButton }, set: { number in
                state.stopRecording()
                state.monitor.cancel()
                preferences.triggerButton = number
            })) {
                Text("右键").tag(Int64(1))
                ForEach(MouseButton.allCases) { button in
                    Text(button.title).tag(preferences.globalProfile.mouseBindings[button.rawValue]?.buttonNumber ?? button.defaultNumber)
                }
                if !([Int64(1)] + MouseButton.allCases.map { preferences.globalProfile.mouseBindings[$0.rawValue]?.buttonNumber ?? $0.defaultNumber }).contains(preferences.triggerButton) {
                    Text(preferences.triggerTitle).tag(preferences.triggerButton)
                }
            }
            Text("绘制键的单击保留原生行为；该键已有的快捷键暂不执行。按住 Option 再按绘制键可临时使用原生拖动。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .onAppear { refreshLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLoginStatus() }
    }

    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginEnabled = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    private func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = "无法修改登录启动：\(error.localizedDescription)" }
        refreshLoginStatus()
    }
}
