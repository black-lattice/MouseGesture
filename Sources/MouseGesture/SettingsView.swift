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
                Toggle("启用手势", isOn: $preferences.enabled).toggleStyle(.switch)
            }.padding(24)
            Divider()
            Form {
                Section("运行状态") {
                    Label(statusText, systemImage: state.running && preferences.enabled ? "checkmark.circle.fill" : "pause.circle")
                        .foregroundStyle(state.running && preferences.enabled ? Color.teal : Color.secondary)
                    if !state.trusted {
                        Text("需要辅助功能权限以识别全局右键手势并执行操作。授权后会自动开始监听。")
                            .foregroundStyle(.secondary)
                        Button("打开辅助功能设置") { state.requestPermission() }
                    } else if !state.running {
                        Text("事件监听未能启动。请尝试重新授权并重启应用；若系统要求输入监控权限，也请开启。")
                        Button("重新检测权限") { state.refreshPermission() }
                        Button("打开输入监控设置") { state.openSettings("Privacy_ListenEvent") }
                    }
                    LabeledContent("最近操作", value: state.lastResult)
                }
                ActionListView(state: state, preferences: preferences)
                Section("识别与显示") {
                    Toggle("显示轨迹与操作提示", isOn: $preferences.showTrail)
                    LabeledContent("最短轨迹 \(Int(preferences.minimumLength)) 点") {
                        Slider(value: $preferences.minimumLength, in: 30...140, step: 10)
                            .frame(width: 220).accessibilityLabel("最短轨迹长度")
                    }
                    Text("普通右键点击会在松开时弹出菜单。按住 Option 再按右键可使用原生右键拖拽。绘制中按 Esc 取消。")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("应用 Bundle ID，以空格或逗号分隔", text: $preferences.excludedBundleIDs, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Text("例如 com.apple.Safari。排除的前台应用中，右键保持原生行为。")
                        .foregroundStyle(.secondary)
                } header: { Text("排除应用") }
                Section {
                    Button("重置手势和快捷键…") { state.stopRecording(); confirmReset = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 740, minHeight: 660)
        .alert("重置手势和快捷键？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("重置", role: .destructive) { state.stopRecording(); preferences.restoreDefaults() }
        } message: { Text("将清除所有手势，并恢复内置功能的默认快捷键和最短轨迹长度。自定义功能的名称和快捷键保留，之后需要重新录制手势。") }
        .onDisappear { state.stopRecording() }
    }

    private var statusText: String {
        if state.customDraft != nil { return "正在编辑自定义功能，动作执行已暂停" }
        if state.gestureRecordingAction != nil { return "正在录制手势，动作执行已暂停" }
        if !state.trusted { return "等待辅助功能授权" }
        if !state.running { return "事件监听尚未启动" }
        return preferences.enabled ? "正在监听右键手势" : "手势已暂停"
    }
}
