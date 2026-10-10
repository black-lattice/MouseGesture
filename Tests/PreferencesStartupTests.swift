// Run the same optimized executable both outside and inside an isolated .app.
// Exercise the production convenience initializer, not the injected store initializer.
let domain = CommandLine.arguments[1]
let mode = CommandLine.arguments[2]
func requireStartup(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
let preferences = Preferences(domain: domain, legacyDomain: domain + ".legacy")
switch mode {
case "write":
    requireStartup(Bundle.main.bundleIdentifier != domain, "开发运行不使用应用 Bundle ID")
    var draft = CustomActionDraft()
    draft.name = "安装启动回归"
    draft.shortcut = .init(keyCode: 7, modifiers: CGEventFlags.maskCommand.rawValue, label: "⌘ X")
    draft.directions = [.down, .left]
    requireStartup(preferences.saveCustomAction(draft) == nil, "开发运行保存自定义功能")
    preferences.minimumLength = 90
case "installed":
    requireStartup(Bundle.main.bundleIdentifier == domain, "以真实应用 Bundle ID 启动")
    requireStartup(UserDefaults(suiteName: domain) == nil, "复现旧版同 Bundle ID suite 返回空值")
    requireStartup(preferences.customAction(for: [.down, .left])?.name == "安装启动回归"
                   && preferences.minimumLength == 90, "安装版读取开发运行的配置")
    requireStartup(UserDefaults.standard.data(forKey: "preferences.v1") != nil, "安装版使用标准配置域")
    preferences.minimumLength = 70
case "read":
    requireStartup(preferences.minimumLength == 70
                   && preferences.customAction(for: [.down, .left])?.shortcut.keyCode == 7,
                   "开发运行读取安装版修改并保留快捷键")
case "fresh":
    requireStartup(Bundle.main.bundleIdentifier == domain, "首次安装在应用环境中验证")
    requireStartup(preferences.enabled && preferences.customActions.isEmpty
                   && preferences.bindings.isEmpty, "首次安装没有配置也能初始化")
case "cleanup":
    UserDefaults.standard.removePersistentDomain(forName: domain)
    UserDefaults.standard.removePersistentDomain(forName: domain + ".legacy")
default: fatalError("未知启动测试阶段")
}
