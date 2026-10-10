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
                Section {
                    ForEach($preferences.bindings) { $binding in
                        Picker(selection: $binding.action) {
                            ForEach(GestureAction.allCases) { action in Text(action.title).tag(action) }
                        } label: {
                            Text(binding.arrows).font(.system(size: 20, weight: .medium, design: .monospaced))
                                .frame(width: 72, alignment: .leading)
                                .accessibilityLabel("手势 \(binding.arrows)")
                        }
                    }
                } header: {
                    Text("手势绑定")
                } footer: {
                    Text("按住右键画出直线或折线，松开执行。操作作用于当前前台应用；关闭标签页在无标签页的应用中可能关闭当前文稿或窗口。")
                }
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
                    ForEach([GestureAction.showDesktop, .spaceLeft, .spaceRight, .missionControl, .closeTab]) { action in
                        LabeledContent(action.title) {
                            Button(state.recordingAction == action ? "请按快捷键 · Esc 取消" : preferences.shortcut(for: action).label) {
                                state.record(action)
                            }.frame(minWidth: 100)
                                .accessibilityLabel("录制\(action.title)快捷键")
                        }
                    }
                    if state.recordingAction != nil { Button("取消录制") { state.stopRecording() } }
                } header: {
                    Text("操作快捷键")
                } footer: {
                    Text("应与系统设置 → 键盘 → 键盘快捷键 → 调度中心中的设置一致。若系统快捷键拦截了录制，可暂时关闭它后录制，再重新开启。左右切换需要已创建多个桌面。关闭窗口直接操作窗口关闭按钮。")
                }
                Section {
                    TextField("应用 Bundle ID，以空格或逗号分隔", text: $preferences.excludedBundleIDs, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Text("例如 com.apple.Safari。排除的前台应用中，右键保持原生行为。")
                        .foregroundStyle(.secondary)
                } header: { Text("排除应用") }
                Section {
                    Button("恢复默认手势和快捷键…") { confirmReset = true }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 620, minHeight: 660)
        .alert("恢复默认手势和快捷键？", isPresented: $confirmReset) {
            Button("取消", role: .cancel) {}
            Button("恢复默认", role: .destructive) { state.stopRecording(); preferences.restoreDefaults() }
        } message: { Text("将重置手势绑定、快捷键和最短轨迹长度。") }
        .onDisappear { state.stopRecording() }
    }

    private var statusText: String {
        if !state.trusted { return "等待辅助功能授权" }
        if !state.running { return "事件监听尚未启动" }
        return preferences.enabled ? "正在监听右键手势" : "手势已暂停"
    }
}
