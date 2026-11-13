import AppKit
import CarapaceCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var state: AppState?
    private var status: StatusController?
    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            NSApp.setActivationPolicy(.regular)
            installMainMenu()
            // 兜底：启动时按住 Option 强制显示菜单栏图标，防止隐藏后找不到入口。
            if NSEvent.modifierFlags.contains(.option) {
                CarapaceDefaults.store.set(true, forKey: "showMenuBarIcon")
            }
            let state = try AppState()
            self.state = state
            if let raw = ProcessInfo.processInfo.environment["CARAPACE_SECTION"],
               let section = AppSection(rawValue: raw) { state.section = section }
            if let raw = ProcessInfo.processInfo.environment["CARAPACE_HOLD_TAB"],
               let tab = HoldTab(rawValue: raw) { state.holdTab = tab }
            if let raw = ProcessInfo.processInfo.environment["CARAPACE_POSITION_ID"],
               let id = Int64(raw) {
                state.section = .positions
                state.selectedPositionId = id
                state.showPositionDetail = true
            }
            if let raw = ProcessInfo.processInfo.environment["CARAPACE_SETTINGS_TAB"],
               let tab = SettingsTab(rawValue: raw) {
                state.section = .settings
                state.settingsTab = tab
            }
            if ProcessInfo.processInfo.environment["CARAPACE_REVIEW_TAB"] == "memory" {
                state.section = .reviews
                state.reviewTab = .memory
            }
            if ProcessInfo.processInfo.environment["CARAPACE_REVIEW_TAB"] == "style" {
                state.section = .reviews
                state.reviewTab = .style
            }
            if ProcessInfo.processInfo.environment["CARAPACE_POSITION_DETAIL"] == "1" {
                state.section = .positions
                state.showPositionDetail = true
            }
            if ProcessInfo.processInfo.environment["CARAPACE_SHOW_INTAKE"] == "1" {
                state.showIntake = true
            }
            if ProcessInfo.processInfo.environment["CARAPACE_WATCH_EDITOR"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    state.activeSheet = .watchEditor(nil)
                }
            }
            if ProcessInfo.processInfo.environment["CARAPACE_SHOW_IMPORT"] == "1" {
                state.showImport = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { state.refresh() }
            let defaults = CarapaceDefaults.store
            if let updated = defaults.string(forKey: "updatedToVersion") {
                defaults.removeObject(forKey: "updatedToVersion")
                if updated == AppVersion.short {
                    state.toastText = "已更新到 \(updated)"
                    NotificationService.shared.send(
                        id: "updated-\(updated)",
                        title: "Carapace 已更新到 \(updated)",
                        body: "数据与设置保持不变。",
                        enabled: CarapaceDefaults.notifyEnabled(.update)
                            && (defaults.object(forKey: "systemNotifications") as? Bool ?? false))
                }
            }
            state.updater.start()
            if ProcessInfo.processInfo.environment["CARAPACE_UPDATE_FORCE"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    state.updater.check(manual: false, force: true)
                }
            }
            let window = MainWindowController(state: state)
            self.mainWindow = window
            self.status = StatusController(
                state: state,
                openApp: { [weak self] in self?.mainWindow?.show(section: .overview) },
                openPosition: { [weak self] id in
                    self?.mainWindow?.show(section: .positions, positionId: id)
                },
                openWatchSheet: { [weak self] sheet in
                    self?.mainWindow?.show(section: .positions)
                    DispatchQueue.main.async { state.activeSheet = sheet }
                })
            if ProcessInfo.processInfo.environment["CARAPACE_SHOW_PANEL"] == "1" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                    self?.status?.showPanel()
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    window.show()
                }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法打开数据库"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    @objc private func checkForUpdates() {
        mainWindow?.show()
        state?.updater.check(manual: true)
    }

    @objc private func toggleMenuBarIcon() {
        guard let state else { return }
        state.showMenuBarIcon.toggle()
        if !state.showMenuBarIcon {
            state.toastText = "菜单栏图标已隐藏；可在 App 菜单或 设置 → 通用 恢复"
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleMenuBarIcon) {
            menuItem.state = (state?.showMenuBarIcon ?? true) ? .on : .off
        }
        return true
    }

    @objc private func openSettings() { mainWindow?.show(section: .settings) }
    @objc private func openOverview() { mainWindow?.show(section: .overview) }
    @objc private func openPositions() { mainWindow?.show(section: .positions) }
    @objc private func openReviews() { mainWindow?.show(section: .reviews) }
    @objc private func refreshQuotes() { state?.refresh() }

    @objc private func newPosition() {
        mainWindow?.show()
        state?.showIntake = true
    }

    @objc private func newWatch() {
        mainWindow?.show()
        state?.activeSheet = .watchEditor(nil)
    }

    @objc private func openImport() {
        mainWindow?.show()
        state?.showImport = true
    }

    private func menuItem(_ title: String, _ action: Selector,
                          _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    /// 标准主菜单：快捷键、撤销/重做、服务、窗口都能走正常响应链。
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Carapace",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(menuItem("检查更新…", #selector(checkForUpdates)))
        appMenu.addItem(menuItem("设置…", #selector(openSettings), ",", .command))
        appMenu.addItem(.separator())

        let servicesItem = NSMenuItem()
        let servicesMenu = NSMenu(title: "服务")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("显示菜单栏图标", #selector(toggleMenuBarIcon)))
        appMenu.addItem(withTitle: "隐藏 Carapace",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "隐藏其他",
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "全部显示",
                        action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Carapace",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "持仓")
        fileMenu.addItem(menuItem("新建持仓", #selector(newPosition), "n"))
        fileMenu.addItem(menuItem("添加观察", #selector(newWatch), "n", [.command, .shift]))
        fileMenu.addItem(menuItem("刷新行情", #selector(refreshQuotes), "r"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(menuItem("导入交割单…", #selector(openImport), "i"))
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "视图")
        viewMenu.addItem(menuItem("总览", #selector(openOverview), "1"))
        viewMenu.addItem(menuItem("持仓", #selector(openPositions), "2"))
        viewMenu.addItem(menuItem("复盘", #selector(openReviews), "3"))
        viewMenu.addItem(menuItem("设置", #selector(openSettings), "4"))
        viewItem.submenu = viewMenu

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(withTitle: "关闭窗口",
                           action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        windowMenu.addItem(withTitle: "最小化",
                           action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "缩放",
                           action: #selector(NSWindow.performZoom(_:)),
                           keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "前置全部窗口",
                           action: #selector(NSApplication.arrangeInFront(_:)),
                           keyEquivalent: "")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { mainWindow?.show() }
        return true
    }
}
