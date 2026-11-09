import SwiftUI
import AppKit
import CarapaceCore

@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private let state: AppState
    private var window: NSWindow?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    func show(section: AppSection? = nil, positionId: Int64? = nil) {
        if let section { state.section = section }
        if let positionId {
            state.selectedPositionId = positionId
            state.positionTab = .plan
            state.section = .positions
        }
        if window == nil {
            let host = NSHostingController(rootView: MainWindowView(state: state))
            let w = NSWindow(contentViewController: host)
            w.title = "Carapace"
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.setContentSize(NSSize(width: 1180, height: 760))
            w.minSize = NSSize(width: 980, height: 640)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("CarapaceMainWindow")
            w.center()
            w.delegate = self
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { true }
}

struct MainWindowView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            UpdateBannerHost(updater: state.updater)
            NavigationSplitView {
            List(selection: $state.section) {
                Section {
                    ForEach(AppSection.allCases) { section in
                        Label(section.title, systemImage: section.icon)
                            .tag(section)
                    }
                }
                            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 196, max: 230)
        } detail: {
            ZStack(alignment: .trailing) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                if state.notifPanelOpen {
                    NotificationPanelView(state: state)
                        .frame(width: 380)
                        .frame(maxHeight: .infinity)
                        .background(Theme.panel)
                        .overlay(alignment: .leading) { Divider() }
                        .shadow(color: .black.opacity(0.12), radius: 18, x: -6, y: 0)
                        .transition(.move(edge: .trailing))
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    state.notifPanelOpen.toggle()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell")
                        if state.unreadNotifications > 0 {
                            Text("\(state.unreadNotifications)")
                                .font(.system(size: 8, weight: .bold))
                                .padding(3)
                                .background(Theme.accent)
                                .foregroundStyle(.white)
                                .clipShape(Circle())
                                .offset(x: 7, y: -7)
                        }
                    }
                }
                .help("通知").accessibilityLabel("通知")
                Button { state.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("刷新行情").accessibilityLabel("刷新行情")
                Menu {
                    Button("新建持仓") { state.showIntake = true }
                    Divider()
                    Button("添加观察") { state.activeSheet = .watchEditor(nil) }
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .help("新建持仓或添加观察")
            }
        }
        .sheet(item: $state.activeSheet) { sheet in
            SheetHost(state: state, sheet: sheet)
        }
        .sheet(isPresented: $state.showIntake) {
            IntakeWizardView(state: state)
        }
        .sheet(isPresented: $state.showImport) {
            ImportWizardView(state: state)
        }
        .overlay(alignment: .bottom) {
            if let text = state.toastText {
                ToastView(text: text)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                            if state.toastText == text { state.toastText = nil }
                        }
                    }
            }
        }
        .onAppear {
            state.refresh()
        }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.section {
        case .overview: OverviewView(state: state)
        case .positions: PositionsView(state: state)
        case .reviews: ReviewsView(state: state)
        case .settings: SettingsViewV5(state: state)
        }
    }
}

struct NotificationPanelView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Text("通知").font(.system(size: 13, weight: .semibold))
                Text("\(state.unreadNotifications) 条未读").font(.system(size: 10)).foregroundStyle(Theme.muted)
                Spacer()
                Button("全部已读") {
                    try? state.store.markAllNotificationsRead()
                    state.loadV5()
                }
                .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.accent)
                Button { state.notifPanelOpen = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted).accessibilityLabel("关闭")
            }
            .padding(12)
            Divider()
            if state.notifications.isEmpty {
                EmptyState(icon: "bell", title: "没有通知", detail: "价格、复盘、草稿和记忆提醒会出现在这里。")
                    .padding(14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.notifications) { n in
                            Button {
                                state.openNotification(n)
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle().fill(n.readAt == nil ? Theme.accent : Color.clear)
                                        .frame(width: 6, height: 6).padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(n.title).font(.system(size: 11.5, weight: .semibold))
                                        if !n.body.isEmpty {
                                            Text(n.body).font(.system(size: 10.5)).foregroundStyle(Theme.muted)
                                        }
                                        Text(notificationKind(n.kind)).font(.system(size: 9)).foregroundStyle(Theme.faint)
                                    }
                                    Spacer()
                                }
                                .padding(.horizontal, 12).padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func notificationKind(_ raw: String) -> String {
        switch raw {
        case "hit": return "价格"
        case "watch": return "观察"
        case "review": return "复盘"
        case "quote": return "行情"
        case "risk": return "仓位"
        case "draft": return "草稿"
        default: return raw
        }
    }
}
