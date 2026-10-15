import AppKit
import Combine
import SwiftUI

@main
enum MouseGestureApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = AppState()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "MouseGesture")
        statusItem = item
        installMainMenu()
        state.preferences.$enabled.sink { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                if !self.state.preferences.enabled { self.state.monitor.cancel() }
                self.updateMenu()
            }
        }.store(in: &subscriptions)
        state.$running.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateMenu() }
        }.store(in: &subscriptions)
        state.start()
        updateMenu()
        showSettings()
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let applicationItem = NSMenuItem()
        let application = NSMenu()
        application.addItem(withTitle: "退出 MouseGesture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        applicationItem.submenu = application
        menu.addItem(applicationItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"),
                                    ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func updateMenu() {
        let menu = NSMenu()
        let title = !state.preferences.enabled ? "手势已暂停" : (state.running ? "手势运行中" : "等待授权 / 监听不可用")
        let status = menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: state.preferences.enabled ? "暂停手势" : "启用手势",
                                  action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        let settings = menu.addItem(withTitle: "设置", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MouseGesture", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem?.menu = menu
        statusItem?.button?.appearsDisabled = !state.preferences.enabled || !state.running
    }

    @objc private func toggleEnabled() {
        state.preferences.enabled.toggle()
        if !state.preferences.enabled { state.monitor.cancel() }
    }

    @objc private func showSettings() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 790),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "MouseGesture 设置"
            window.contentView = NSHostingView(rootView: SettingsView(state: state, preferences: state.preferences))
            window.minSize = NSSize(width: 760, height: 680)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidResignKey(_ notification: Notification) { state.stopRecording() }
    func windowWillClose(_ notification: Notification) {
        state.resetCustomDrafts()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { state.stop() }
}
