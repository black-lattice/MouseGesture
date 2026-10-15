import SwiftUI
import UniformTypeIdentifiers

enum ApplicationIdentity {
    static func url(_ id: String) -> URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
    static func name(_ id: String) -> String {
        guard let url = url(id) else { return id }
        return FileManager.default.displayName(atPath: url.path)
    }
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.title = "选择应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}

struct ApplicationLabel: View {
    let id: String
    var body: some View {
        HStack(spacing: 8) {
            if let url = ApplicationIdentity.url(id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "app.dashed").frame(width: 24, height: 24).accessibilityHidden(true)
            }
            Text(ApplicationIdentity.name(id)).help(id)
        }
    }
}

struct ApplicationProfileView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @State private var confirmDelete = false

    var body: some View {
        Section("配置范围") {
            HStack {
                Picker("编辑配置", selection: Binding(get: { preferences.editingBundleID }, set: { id in
                    state.resetCustomDrafts()
                    state.monitor.cancel()
                    preferences.editingBundleID = id
                    state.resetCustomDrafts()
                })) {
                    Text("全局配置").tag("")
                    ForEach(preferences.profiles.keys.sorted(), id: \.self) { id in
                        Text(ApplicationIdentity.name(id)).tag(id)
                    }
                }
                Button("添加应用") {
                    state.stopRecording()
                    if let id = ApplicationIdentity.choose() {
                        if preferences.profiles[id] == nil { preferences.profiles[id] = ApplicationProfile() }
                        preferences.editingBundleID = id
                        state.resetCustomDrafts()
                    }
                }
                if !preferences.editingBundleID.isEmpty {
                    Button("删除专属配置", role: .destructive) { confirmDelete = true }
                }
            }
            Text(preferences.editingBundleID.isEmpty
                 ? "全局配置适用于所有未设置专属绑定的应用。"
                 : "下方只编辑此应用的专属绑定；相同手势优先使用专属操作，其他手势沿用全局配置。清除专属手势后恢复全局绑定。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .alert("删除此应用的专属配置？", isPresented: $confirmDelete) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                state.stopRecording()
                preferences.profiles.removeValue(forKey: preferences.editingBundleID)
                preferences.editingBundleID = ""
                state.resetCustomDrafts()
            }
        } message: { Text("该应用将恢复使用全局配置。") }
    }
}

struct ExcludedApplicationsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    var body: some View {
        Section("排除应用（所有配置共用）") {
            ForEach(preferences.excludedApplications, id: \.self) { id in
                HStack {
                    ApplicationLabel(id: id)
                    Spacer()
                    Button("移除") { preferences.setExcluded(id, excluded: false) }
                        .accessibilityLabel("移除排除应用 \(ApplicationIdentity.name(id))")
                }
            }
            Button("添加排除应用") {
                state.stopRecording()
                if let id = ApplicationIdentity.choose() { preferences.setExcluded(id, excluded: true) }
            }
            Text("排除的应用保留原生鼠标行为。也可从菜单栏直接停用当前应用的手势。")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}
