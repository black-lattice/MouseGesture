let migrationSuite = "MouseGesture.MigrationTests.\(UUID().uuidString)"
let migrationDefaults = UserDefaults(suiteName: migrationSuite)!
let legacyMigrationDefaults = UserDefaults(suiteName: migrationSuite + ".legacy")!
defer {
    migrationDefaults.removePersistentDomain(forName: migrationSuite)
    legacyMigrationDefaults.removePersistentDomain(forName: migrationSuite + ".legacy")
}
var migrationCount = 0
func checkMigration(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { print("失败：\(name)"); exit(1) }
    migrationCount += 1
}
let legacyPreferences = Preferences(defaults: legacyMigrationDefaults)
var oldDraft = CustomActionDraft()
oldDraft.name = "旧版截图"
oldDraft.shortcut = .init(keyCode: 7, modifiers: CGEventFlags.maskCommand.union(.maskShift).rawValue, label: "⇧ ⌘ X")
oldDraft.directions = [.down, .left]
checkMigration(legacyPreferences.saveCustomAction(oldDraft) == nil, "旧运行方式保存自定义功能")
legacyPreferences.enabled = false
legacyPreferences.minimumLength = 90
let legacyData = legacyMigrationDefaults.data(forKey: "preferences.v1")
let migrated = Preferences(defaults: migrationDefaults, legacyDefaults: legacyMigrationDefaults)
checkMigration(migrated.customAction(for: oldDraft.directions)?.shortcut == oldDraft.shortcut, "安装后迁移完整快捷键和手势")
checkMigration(!migrated.enabled && migrated.minimumLength == 90, "首次安装保留旧版其他设置")
checkMigration(legacyMigrationDefaults.data(forKey: "preferences.v1") == legacyData, "迁移不会改写原配置")
let persistedData = migrationDefaults.data(forKey: "preferences.v1")
_ = Preferences(defaults: migrationDefaults, legacyDefaults: legacyMigrationDefaults)
checkMigration(migrationDefaults.data(forKey: "preferences.v1") == persistedData, "启动读取不触发半初始化配置保存")
migrated.deleteCustomAction(oldDraft.id)
checkMigration(Preferences(defaults: migrationDefaults, legacyDefaults: legacyMigrationDefaults).customActions.isEmpty,
               "用户删除迁移条目后重启不会反复恢复")

// Simulate an installed app that already has bindings and its own custom actions.
migrationDefaults.removePersistentDomain(forName: migrationSuite)
let installedPreferences = Preferences(defaults: migrationDefaults)
installedPreferences.minimumLength = 60
checkMigration(installedPreferences.bind(oldDraft.directions, to: .spaceLeft), "安装版已经占用旧手势")
var installedDraft = CustomActionDraft()
installedDraft.name = "安装版功能"
installedDraft.shortcut = oldDraft.shortcut
installedDraft.directions = [.up, .right]
checkMigration(installedPreferences.saveCustomAction(installedDraft) == nil, "安装版已有独立功能")
let merged = Preferences(defaults: migrationDefaults, legacyDefaults: legacyMigrationDefaults)
checkMigration(merged.enabled && merged.minimumLength == 60, "合并时保留安装版当前设置")
checkMigration(merged.customActions.count == 2 && merged.customAction(for: installedDraft.directions)?.id == installedDraft.id,
               "合并只补回缺失功能，不覆盖安装版功能")
checkMigration(merged.action(for: oldDraft.directions) == .spaceLeft
               && merged.customActions.first(where: { $0.id == oldDraft.id })?.pattern == "",
               "冲突时保留现有绑定，恢复功能但等待重新录制手势")
checkMigration(merged.customActions.first(where: { $0.id == oldDraft.id })?.shortcut == oldDraft.shortcut,
               "手势冲突不会丢失旧功能的名称和快捷键")

migrationDefaults.removePersistentDomain(forName: migrationSuite)
let sameName = Preferences(defaults: migrationDefaults)
var renamed = installedDraft
renamed.name = oldDraft.name
checkMigration(sameName.saveCustomAction(renamed) == nil, "安装版保存同名新记录")
let deduplicated = Preferences(defaults: migrationDefaults, legacyDefaults: legacyMigrationDefaults)
checkMigration(deduplicated.customActions.count == 1 && deduplicated.customActions[0].id == renamed.id,
               "旧同名条目不会覆盖用户重新创建的功能")
print("旧配置迁移测试通过：\(migrationCount) 项")
