import SwiftUI

enum ActionRowLayout {
    static let spacing: CGFloat = 12
    static let shortcutWidth: CGFloat = 128
    static let gestureWidth: CGFloat = 120
    static let actionWidth: CGFloat = 208
}

struct ActionListView: View {
    @ObservedObject var state: AppState
    @ObservedObject var preferences: Preferences
    @State private var query = ""
    @State private var category: ActionCategory?

    private var actions: [GestureAction] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return GestureAction.available.filter {
            (category == nil || $0.category == category)
                && (search.isEmpty || $0.title.localizedStandardContains(search) || $0.category.title.localizedStandardContains(search))
        }
    }
    private var customActions: [CustomAction] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return preferences.customActions.filter {
            (category == nil || category == .custom)
                && (search.isEmpty || $0.name.localizedStandardContains(search) || ActionCategory.custom.title.localizedStandardContains(search))
        }
    }

    var body: some View {
        Section {
            TextField("搜索功能名称", text: $query)
                .textFieldStyle(.roundedBorder).accessibilityLabel("搜索功能名称")
            HStack {
                Picker("分类", selection: $category) {
                    Text("全部功能").tag(Optional<ActionCategory>.none)
                    ForEach(ActionCategory.allCases) { Text($0.title).tag(Optional($0)) }
                }.frame(maxWidth: 300)
                Spacer()
                Text("\(actions.count + customActions.count) 项功能").foregroundStyle(.secondary)
            }
            Text("内置功能的快捷键仅供查看，点击手势可录制；只有自定义功能可以录入或修改快捷键。尚未录制手势的功能不会触发。")
                .font(.callout).foregroundStyle(.secondary)
            if actions.isEmpty && customActions.isEmpty && state.customDraft == nil {
                Text(category == .custom && query.isEmpty ? "还没有已保存的自定义功能，可在下方空白行填写。" : "没有匹配的功能，请更换关键词或分类。")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("功能、快捷键与手势")
        }
        .onChange(of: query) { _ in state.stopRecording() }
        .onChange(of: category) { _ in state.stopRecording() }

        CustomActionsView(state: state, preferences: preferences, actions: customActions)

        ForEach(ActionCategory.allCases) { section in
            let matches = actions.filter { $0.category == section }
            if !matches.isEmpty {
                Section {
                    HStack(spacing: ActionRowLayout.spacing) {
                        Text("功能").frame(maxWidth: .infinity, alignment: .leading)
                        Text("快捷键").frame(width: ActionRowLayout.shortcutWidth)
                        Text("手势").frame(width: ActionRowLayout.gestureWidth)
                        Color.clear.frame(width: ActionRowLayout.actionWidth, height: 1).accessibilityHidden(true)
                    }.font(.caption).foregroundStyle(.secondary)
                    ForEach(matches) { action in
                        VStack(alignment: .leading, spacing: 10) {
                            actionRow(action)
                            if state.gestureRecordingAction == action {
                                GestureRecordingView(action: action, preferences: preferences) { state.stopRecording() }
                            }
                        }
                    }
                } header: {
                    Text(section.title)
                } footer: {
                    Text(section.hint)
                }
            }
        }
    }

    private func actionRow(_ action: GestureAction) -> some View {
        let gesture = preferences.gestures(for: action)
        return HStack(spacing: ActionRowLayout.spacing) {
            Text(action.title).frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.85).help(action.title)
            if action.usesShortcut {
                Text(preferences.shortcut(for: action)?.label ?? "未设置")
                    .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .frame(width: ActionRowLayout.shortcutWidth)
                    .accessibilityLabel("\(action.title)快捷键，只读")
                    .help("内置功能快捷键不可修改；需要其他组合时可添加自定义功能")
            } else {
                Text("窗口关闭按钮").font(.callout).foregroundStyle(.secondary)
                    .frame(width: ActionRowLayout.shortcutWidth).help("直接点击当前窗口的关闭按钮，无需快捷键")
            }
            Button {
                state.recordGesture(action)
            } label: {
                Text(gesture.isEmpty ? "录制手势" : gesture)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: ActionRowLayout.gestureWidth)
            .disabled(state.gestureRecordingAction == action)
            .accessibilityLabel("录制\(action.title)手势")
            .help(gesture.isEmpty ? "点击录制手势" : "当前手势：\(gesture)，点击重新录制")
            Button {
                state.stopRecording()
                preferences.clearGesture(for: action)
            } label: {
                Text("清除").frame(minWidth: 32).fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.bordered).fixedSize(horizontal: true, vertical: false)
            .frame(width: ActionRowLayout.actionWidth, alignment: .trailing).disabled(gesture.isEmpty)
            .accessibilityLabel("清除\(action.title)手势")
        }
    }
}
