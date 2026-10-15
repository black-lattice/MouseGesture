import SwiftUI
import GestureCore

struct GestureReferenceView: View {
    @ObservedObject var preferences: Preferences
    let bundleID: String?
    private var rows: [(String, String, String)] {
        let profile = preferences.resolvedProfile(for: bundleID)
        var result = profile.bindings.filter { $0.action.isAvailable(in: bundleID) }.map {
            ($0.pattern, $0.arrows, $0.action.title)
        }
        result += profile.customActions.filter { !$0.pattern.isEmpty }.map { ($0.pattern, $0.arrows, $0.name) }
        return result.sorted { $0.0 < $1.0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("手势速查").font(.title2.bold())
            Text(bundleID.map(ApplicationIdentity.name) ?? "全局配置").foregroundStyle(.secondary)
            if preferences.excludes(bundleID) {
                Label("此应用已排除，手势和按键绑定不会执行。", systemImage: "pause.circle")
            } else if !preferences.enabled {
                Label("手势与按键已暂停。", systemImage: "pause.circle")
            }
            Text("按住\(preferences.triggerTitle)绘制；应用专属手势优先，其余沿用全局配置。")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 10) {
                    if rows.isEmpty { Text("尚未配置可用手势，请在设置中录制。").foregroundStyle(.secondary) }
                    ForEach(rows, id: \.0) { row in
                        HStack {
                            Text(row.1).font(.system(.body, design: .monospaced)).frame(width: 110, alignment: .leading)
                            Text(row.2).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    ForEach(MouseButton.allCases) { button in
                        let binding = preferences.mouseBinding(for: button, bundleID: bundleID)
                        if let shortcut = binding.shortcut {
                            HStack {
                                Text(button.title).frame(width: 110, alignment: .leading)
                                Text(binding.buttonNumber == preferences.triggerButton ? "用作绘制键，快捷键暂停" : shortcut.label)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(24).frame(minWidth: 460, minHeight: 360)
    }
}
