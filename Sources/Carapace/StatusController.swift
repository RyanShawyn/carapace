import AppKit
import SwiftUI
import Combine
import CarapaceCore

@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let state: AppState
    private let item: NSStatusItem
    private let popover = NSPopover()
    private var hosting: NSHostingController<PanelView>!
    private var cancellables = Set<AnyCancellable>()
    private let pinned = ProcessInfo.processInfo.environment["CARAPACE_PIN_PANEL"] == "1"
    private let openApp: (() -> Void)?
    private let openPosition: ((Int64) -> Void)?
    private let openWatchSheet: ((AppState.ActiveSheet) -> Void)?

    init(state: AppState,
         openApp: (() -> Void)? = nil,
         openPosition: ((Int64) -> Void)? = nil,
         openWatchSheet: ((AppState.ActiveSheet) -> Void)? = nil) {
        self.state = state
        self.openApp = openApp
        self.openPosition = openPosition
        self.openWatchSheet = openWatchSheet
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        hosting = NSHostingController(rootView: PanelView(
            state: state,
            // 从面板跳去主窗口时先收起面板，避免面板浮在主窗口上面。
            onOpenApp: { [weak self] in self?.dismiss { openApp?() } },
            onOpenPosition: { [weak self] id in self?.dismiss { openPosition?(id) } },
            onEditWatch: { [weak self] id in
                self?.dismiss { openWatchSheet?(.watchEditor(id)) }
            },
            onConvertWatch: { [weak self] id in
                self?.dismiss { openWatchSheet?(.convertWatch(id)) }
            }))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = pinned ? .applicationDefined : .transient
        popover.delegate = self

        state.$alerts
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateIcon()
                self?.resize()
            }
            .store(in: &cancellables)
        state.$muted
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateIcon() }
            .store(in: &cancellables)
        state.$expanded
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.resize() }
            .store(in: &cancellables)
        DistributedNotificationCenter.default.addObserver(
            self, selector: #selector(appearanceChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)

        updateIcon()
    }

    private func updateIcon() {
        let glyph = state.iconName
        item.button?.image = MenuGlyph.image(for: glyph, color: color(for: glyph))
        item.button?.toolTip = state.iconTooltip
        item.button?.setAccessibilityLabel("Carapace")
    }

    private func color(for glyph: String) -> NSColor? {
        switch glyph {
        case "turtle.trigger": return .systemBlue
        case "turtle.watch": return .systemOrange
        case "turtle.error": return .systemOrange
        default: return nil
        }
    }

    @objc private func appearanceChanged() {
        DispatchQueue.main.async { [weak self] in self?.updateIcon() }
    }

    private func resize() {
        guard popover.isShown else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.popover.contentSize = self.hosting.preferredContentSize
        }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    /// 收起面板后再执行跳转动作（打开主窗口 / 定位持仓）。
    private func dismiss(_ action: @escaping () -> Void) {
        item.button?.highlight(false)
        guard popover.isShown else { action(); return }
        popover.performClose(nil)
        DispatchQueue.main.async { action() }
    }

    func showPanel() {
        guard !popover.isShown, let button = item.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        if popover.isShown { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        button.highlight(true)
    }

    func popoverDidShow(_ notification: Notification) {
        state.startLive()
    }

    func popoverDidClose(_ notification: Notification) {
        item.button?.highlight(false)
        state.stopLive()
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(item("打开 Carapace", #selector(menuOpen)))
        let version = NSMenuItem(title: "Carapace \(AppVersion.short)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        menu.addItem(item("检查更新…", #selector(menuCheckUpdates)))
        menu.addItem(.separator())
        menu.addItem(item("退出 Carapace", #selector(menuQuit)))
        item.menu = menu
        item.button?.performClick(nil)
        item.menu = nil
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let value = NSMenuItem(title: title, action: action, keyEquivalent: "")
        value.target = self
        return value
    }

    @objc private func menuOpen() { openApp?() }
    @objc private func menuCheckUpdates() {
        showPanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.state.updater.check(manual: true)
        }
    }
    @objc private func menuQuit() { NSApp.terminate(nil) }
}

/// 菜单栏字形：龟壳 + 头 + 腿，按状态叠加标记。
enum MenuGlyph {
    static func image(for name: String, color: NSColor? = nil) -> NSImage {
        let ink = color ?? .black
        // 22×18 画布 → 22×22 图像；1.07 再把字形放大一点，整体平移保持居中。
        let k = 22.0 / 18.0 * 1.07
        let offset = 11.0 - 9.0 * k
        let img = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            NSGraphicsContext.current?.cgContext.concatenate(
                CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: offset, ty: offset))
            ink.setFill()
            ink.setStroke()

            NSBezierPath(roundedRect: NSRect(x: 3.3, y: 3.4, width: 2.8, height: 3.0),
                         xRadius: 1.3, yRadius: 1.3).fill()
            NSBezierPath(roundedRect: NSRect(x: 8.7, y: 3.4, width: 2.8, height: 3.0),
                         xRadius: 1.3, yRadius: 1.3).fill()
            NSBezierPath(ovalIn: NSRect(x: 12.7, y: 6.0, width: 4.4, height: 4.0)).fill()

            let shell = NSBezierPath()
            shell.move(to: NSPoint(x: 1.4, y: 5.9))
            shell.curve(to: NSPoint(x: 13.0, y: 5.9),
                        controlPoint1: NSPoint(x: 1.7, y: 14.9),
                        controlPoint2: NSPoint(x: 12.7, y: 14.9))
            shell.close()
            shell.lineWidth = 1.45

            switch name {
            case "circle.dotted":
                shell.setLineDash([1.3, 1.3], count: 2, phase: 0)
                shell.stroke()
            case "turtle.trigger":
                // 空心壳 + 右上角圆点，表示有价位触发未确认。
                shell.stroke()
                NSBezierPath(ovalIn: NSRect(x: 12.6, y: 12.4, width: 4.6, height: 4.6)).fill()
            case "turtle.watch":
                // 观察提醒：空心壳 + 壳内小三角，和持仓触发区分。
                shell.stroke()
                let eye = NSBezierPath()
                eye.move(to: NSPoint(x: 5.4, y: 8.2))
                eye.line(to: NSPoint(x: 9.6, y: 8.2))
                eye.line(to: NSPoint(x: 7.5, y: 10.6))
                eye.close()
                eye.fill()
            case "turtle.error":
                // 空心壳 + 壳内感叹号，表示行情异常未确认。
                shell.stroke()
                NSBezierPath(roundedRect: NSRect(x: 6.7, y: 8.4, width: 1.25, height: 3.1),
                             xRadius: 0.62, yRadius: 0.62).fill()
                NSBezierPath(ovalIn: NSRect(x: 6.6, y: 6.6, width: 1.45, height: 1.45)).fill()
            case "turtle.review":
                // 空心壳 + 壳内圆点，表示复盘逾期。
                shell.stroke()
                NSBezierPath(ovalIn: NSRect(x: 5.9, y: 7.1, width: 2.6, height: 2.6)).fill()
            default:
                shell.stroke()
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }
}
