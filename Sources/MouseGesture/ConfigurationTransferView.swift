import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationTransferView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @State private var pending: ConfigurationImport?
    @State private var showPreview = false
    @State private var message: String?
    @State private var confirmReplace = false

    var body: some View {
        Section("配置备份") {
            HStack {
                Button("导出配置") { exportFile() }
                Button("导入配置") { importFile() }
            }
            Text("包含全局与应用专属绑定、排除列表及轨迹设置；登录启动由当前电脑的系统设置管理。")
                .font(.callout).foregroundStyle(.secondary)
            if let message { Text(message).font(.callout).textSelection(.enabled) }
        }
        .sheet(isPresented: $showPreview) {
            VStack(alignment: .leading, spacing: 16) {
                Text("导入配置预览").font(.title2.bold())
                if let pending {
                    Text("全局手势 \(pending.replacement.bindings.count) 项，自定义功能 \(pending.replacement.customActions?.count ?? 0) 项，应用专属配置 \(pending.replacement.profiles?.count ?? 0) 项。")
                    Text("合并会保留本机已有绑定和外观设置，跳过以下 \(pending.conflicts.count) 项冲突，并合并排除列表。")
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            if pending.conflicts.isEmpty { Text("没有冲突，可以直接合并。") }
                            ForEach(Array(pending.conflicts.enumerated()), id: \.offset) { _, conflict in Text(conflict) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 180)
                    HStack {
                        Button("取消") { showPreview = false }
                        Spacer()
                        Button("全部覆盖", role: .destructive) { confirmReplace = true }
                        Button("合并并保留本机冲突项") { apply(pending.merged) }.keyboardShortcut(.defaultAction)
                    }
                }
            }.padding(24).frame(width: 580)
            .alert("覆盖本机全部配置？", isPresented: $confirmReplace) {
                Button("取消", role: .cancel) {}
                Button("覆盖", role: .destructive) { if let pending { apply(pending.replacement) } }
            } message: { Text("现有手势、应用配置、排除列表和外观设置将被替换。建议先导出备份。") }
        }
    }

    private func exportFile() {
        state.stopRecording()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MouseGesture-配置.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try preferences.exportConfiguration().write(to: url, options: .atomic)
            message = "已导出：\(url.lastPathComponent)"
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    private func importFile() {
        state.stopRecording()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5_000_000 else { throw ConfigurationError.invalid("配置文件不能超过 5 MB。") }
            pending = try preferences.prepareImport(Data(contentsOf: url))
            showPreview = true
        } catch { message = "导入失败，原配置未改变：\(error.localizedDescription)" }
    }

    private func apply(_ value: Preferences.Saved) {
        state.stopRecording()
        state.monitor.cancel()
        preferences.apply(value)
        state.resetCustomDrafts()
        showPreview = false
        message = "配置已导入。"
    }
}
