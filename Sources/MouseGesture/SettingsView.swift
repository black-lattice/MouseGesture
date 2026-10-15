import SwiftUI

struct SettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 32)).foregroundStyle(.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("MouseGesture").font(.title2.bold())
                    Text("用一笔手势，让操作更顺手").foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("启用手势与按键", isOn: $preferences.enabled).toggleStyle(.switch)
            }.padding(24)
            Divider()
            Form {
                Section("运行状态") {
                    Label(statusText, systemImage: state.running && preferences.enabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(state.running && preferences.enabled ? Color.teal : Color.secondary)
                    if !state.trusted {
                        Text("需要辅助功能权限以识别全局鼠标手势、鼠标按键并执行操作。授权后会自动开始监听。")
                            .foregroundStyle(.secondary)
                        Button("打开辅助功能设置") { state.requestPermission() }
                    } else if !state.running && preferences.enabled {
                        Text("事件监听未能启动。请尝试重新授权并重启应用；若系统要求输入监控权限，也请开启。")
                        Button("重新检测权限") { state.refreshPermission() }
                        Button("打开输入监控设置") { state.openSettings("Privacy_ListenEvent") }
                    }
                    LabeledContent("最近操作", value: state.lastResult)
                }
                GeneralSettingsView(state: state, preferences: preferences)
                ApplicationProfileView(state: state, preferences: preferences)
                MouseButtonSettingsView(state: state, preferences: preferences)
                ActionListView(state: state, preferences: preferences)
                Section("识别与显示") {
                    Toggle("显示轨迹", isOn: $preferences.showTrail)
                    Toggle("显示停顿操作提示", isOn: $preferences.showHint)
                    Picker("轨迹颜色", selection: $preferences.trailColor) {
                        ForEach(TrailColor.allCases) { Text($0.title).tag($0) }
                    }
                    LabeledContent("轨迹粗细 \(Int(preferences.trailWidth)) 点") {
                        Slider(value: $preferences.trailWidth, in: 2...10, step: 1).frame(width: 220)
                            .accessibilityLabel("轨迹粗细")
                    }
                    RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: preferences.trailColor.color))
                        .frame(width: 160, height: preferences.trailWidth).padding(.vertical, 6)
                        .accessibilityLabel("轨迹颜色和粗细预览")
                    LabeledContent("最短轨迹 \(Int(preferences.minimumLength)) 点") {
                        Slider(value: $preferences.minimumLength, in: 30...140, step: 10)
                            .frame(width: 220).accessibilityLabel("最短轨迹长度")
                    }
                    Text("绘制键的普通点击在松开时补发。按住 Option 再按绘制键可使用原生拖动。绘制中按 Esc 取消。")
                        .foregroundStyle(.secondary)
                }
                ExcludedApplicationsView(state: state, preferences: preferences)
                ConfigurationTransferView(state: state, preferences: preferences)
                Section {
                    Button("重置当前配置的手势和快捷键") { state.stopRecording(); confirmReset = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 740, minHeight: 660)
        .alert("重置当前配置的手势和快捷键？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { state.stopRecording(); preferences.restoreDefaults() }
        } message: { Text("将清除当前编辑配置的手势与鼠标按键绑定，并恢复内置快捷键；重置全局配置时也恢复最短轨迹长度。自定义功能的名称和快捷键保留，之后需要重新录制手势。") }
        .onDisappear { state.stopRecording() }
    }

    private var statusText: String {
        if state.recordingMouseShortcut != nil { return "正在录制鼠标按键快捷键，动作执行已暂停" }
        if state.recordingMouseButton != nil { return "正在识别鼠标按键，动作执行已暂停" }
        if state.customDraft != nil { return "正在编辑自定义功能，动作执行已暂停" }
        if state.gestureRecordingAction != nil { return "正在录制手势，动作执行已暂停" }
        if !state.trusted { return "等待辅助功能授权" }
        if !preferences.enabled { return "手势与按键已暂停" }
        if !state.running { return "事件监听尚未启动" }
        return "正在监听\(preferences.triggerTitle)手势与鼠标按键"
    }
}
