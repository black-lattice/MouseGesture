import SwiftUI
import GestureCore

struct CustomActionsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    let actions: [CustomAction]
    let onSaved: () -> Void
    @State private var pendingDeletion: CustomAction?

    var body: some View {
        Section {
            HStack(spacing: ActionRowLayout.spacing) {
                Text("名称").frame(maxWidth: .infinity, alignment: .leading)
                Text("快捷键").frame(width: ActionRowLayout.shortcutWidth)
                Text("手势").frame(width: ActionRowLayout.gestureWidth)
                Color.clear.frame(width: ActionRowLayout.actionWidth, height: 1).accessibilityHidden(true)
            }.font(.caption).foregroundStyle(.secondary)
            ForEach(actions.filter { action in !state.customDrafts.contains { $0.id == action.id } }) { action in
                HStack(spacing: ActionRowLayout.spacing) {
                    Text(action.name).frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1).help(action.name)
                    Button { state.editCustomAction(action) } label: {
                        Text(action.shortcut.label).frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(width: ActionRowLayout.shortcutWidth).accessibilityLabel("编辑\(action.name)快捷键")
                    Button { state.editCustomAction(action) } label: {
                        Text(action.pattern.isEmpty ? "录制手势" : action.arrows)
                            .font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity)
                    }.frame(width: ActionRowLayout.gestureWidth).accessibilityLabel("编辑\(action.name)手势")
                    Menu {
                        Button("编辑") { state.editCustomAction(action) }
                        Button("清除手势") {
                            state.stopRecording()
                            preferences.clearCustomGesture(action.id)
                        }.disabled(action.pattern.isEmpty)
                        Button("删除…", role: .destructive) {
                            state.stopRecording()
                            pendingDeletion = action
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }.frame(width: 36).frame(width: ActionRowLayout.actionWidth, alignment: .trailing)
                        .accessibilityLabel("\(action.name)的更多操作")
                }
            }
            ForEach($state.customDrafts) { $draft in
                CustomActionEditorView(state: state, preferences: preferences, draft: $draft, onSaved: onSaved)
            }
        } header: {
            HStack {
                Text("自定义")
                Spacer()
                Button { state.addCustomDraft() } label: {
                    Image(systemName: "plus")
                }.accessibilityLabel("添加自定义功能行").help("增加一行自定义功能")
            }
        } footer: {
            Text(ActionCategory.custom.hint)
        }
        .alert("删除自定义功能？", isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
               presenting: pendingDeletion) { action in
            Button("取消", role: .cancel) { pendingDeletion = nil }
            Button("删除", role: .destructive) {
                preferences.deleteCustomAction(action.id)
                state.ensureCustomDraft()
                pendingDeletion = nil
            }
        } message: { action in
            Text("将删除“\(action.name)”及其手势绑定。")
        }
    }
}

private struct CustomActionEditorView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @Binding var draft: CustomActionDraft
    let onSaved: () -> Void
    private var isActive: Bool { state.customDraft?.id == draft.id }
    private var recordingShortcut: Bool { isActive && state.recordingCustomShortcut }
    @State private var recordingGesture = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: ActionRowLayout.spacing) {
                TextField("输入功能名称", text: $draft.name)
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity).accessibilityLabel("自定义功能名称")
                    .onTapGesture { if !isActive { state.stopRecording() } }
                Button {
                    recordingGesture = false
                    state.activateCustomDraft(draft.id)
                    state.recordCustomShortcut()
                } label: {
                    Text(recordingShortcut ? "请按快捷键…" : draft.shortcut?.label ?? "录入快捷键")
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(width: ActionRowLayout.shortcutWidth)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("录入自定义快捷键")
                .help("与软件中设置的快捷键保持一致。录制时会临时拦截按键，松开后完成录入。")
                Button {
                    state.activateCustomDraft(draft.id)
                    recordingGesture = true
                } label: {
                    Text(draft.directions.isEmpty ? "录制手势" : draft.directions.map(\.arrow).joined(separator: " "))
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(width: ActionRowLayout.gestureWidth).disabled(draft.shortcut == nil || recordingGesture)
                .accessibilityLabel("录制自定义手势")
                .help("点击展开手势录制区域")
                HStack(spacing: 8) {
                    Button("保存") { save(draft) }
                        .frame(width: 36)
                        .disabled(preferences.validationError(for: draft) != nil || recordingShortcut || recordingGesture)
                        .accessibilityLabel("保存自定义功能并生效")
                    Button { state.removeCustomDraft(draft.id) } label: {
                        Image(systemName: "trash").frame(width: 24, height: 24)
                    }.buttonStyle(.borderless).foregroundStyle(.secondary)
                        .accessibilityLabel("移除此行草稿").help("放弃此行未保存的内容")
                }.frame(width: ActionRowLayout.actionWidth, alignment: .trailing)
            }
            if recordingShortcut {
                HStack {
                    Text("按下并松开快捷键 · Esc 取消").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("取消录入") { state.stopRecording() }
                }
            }
            if let error = draft.shortcutError {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
            if recordingGesture {
                Text("在下方区域按住右键绘制，支持上下左右直线或最多四段折线。录制成功后点击本行“保存”生效。")
                    .font(.callout).foregroundStyle(.secondary)
                GestureRecordingPad(minimumLength: preferences.minimumLength, onStart: {
                    state.stopCustomShortcutRecording()
                    draft.directions = []
                    draft.gestureError = nil
                }, onComplete: { directions in
                    draft.directions = directions ?? []
                    draft.gestureError = directions == nil ? "未识别到有效手势，请重新绘制并达到最短轨迹长度。" : nil
                    if let directions, preferences.conflict(for: directions, customID: draft.id) == nil {
                        finishGestureRecording()
                    }
                }, onCancel: { finishGestureRecording() })
                .frame(height: 320)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
                .accessibilityLabel("自定义功能的手势录制区域")
                Button("收起录制区域") { finishGestureRecording() }
            }
            if let error = draft.gestureError ?? validationFeedback(draft) {
                Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red)
            }
        }
        .onChange(of: isActive) { active in
            if !active { recordingGesture = false }
        }
        .onChange(of: recordingShortcut) { recording in
            if !recording && isActive && !recordingGesture { state.stopRecording() }
        }
        .onExitCommand {
            if isActive { finishGestureRecording() }
            else { state.removeCustomDraft(draft.id) }
        }
    }

    private func finishGestureRecording() {
        recordingGesture = false
        if isActive { state.stopRecording() }
    }

    private func save(_ candidate: CustomActionDraft) {
        if let error = preferences.saveCustomAction(candidate) {
            draft.gestureError = error
        } else {
            state.lastResult = "已保存自定义功能：\(draft.name.trimmingCharacters(in: .whitespacesAndNewlines))"
            state.removeCustomDraft(candidate.id)
            onSaved()
        }
    }

    private func validationFeedback(_ draft: CustomActionDraft) -> String? {
        guard !draft.directions.isEmpty else { return nil }
        return preferences.validationError(for: draft)
    }
}
