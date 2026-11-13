import Foundation
import SwiftUI
import CarapaceCore

/// 统一从 Info.plist 读取版本，避免设置页和右键菜单写死旧版本号。
enum AppVersion {
    static var short: String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !value.isEmpty {
            return value
        }
        // 裸二进制（swift run / dev-run）没有 Info.plist，回退到构建版本，
        // 否则更新器会把 "—" 当成旧版本并尝试自动更新。
        return CarapaceBuild.version
    }
}

private let darwinCallback: CFNotificationCallback = { _, observer, _, _, _ in
    guard let observer else { return }
    let state = Unmanaged<AppState>.fromOpaque(observer).takeUnretainedValue()
    Task { @MainActor in
        state.reloadPreferences()
        state.load()
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview, positions, reviews, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "总览"
        case .positions: return "持仓"
        case .reviews: return "复盘"
        case .settings: return "设置"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .positions: return "list.bullet"
        case .reviews: return "arrow.triangle.2.circlepath"
        case .settings: return "gearshape"
        }
    }
}

enum HoldTab: String, CaseIterable, Identifiable {
    case positions, watch, plans, ledger
    var id: String { rawValue }
    var title: String {
        switch self {
        case .positions: return "持仓"
        case .watch: return "观察"
        case .plans: return "计划"
        case .ledger: return "流水"
        }
    }
}

enum PositionTab: String, CaseIterable, Identifiable {
    case plan, ledger, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plan: return "计划"
        case .ledger: return "流水"
        case .review: return "复盘"
        }
    }
}

enum ReviewTab: String, CaseIterable, Identifiable {
    case reviews, memory, style
    var id: String { rawValue }
    var title: String {
        switch self {
        case .reviews: return "复盘"
        case .memory: return "记忆"
        case .style: return "风格"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, automation, notify, data, update, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "通用"
        case .automation: return "自动化"
        case .notify: return "通知"
        case .data: return "行情与数据"
        case .update: return "更新"
        case .about: return "关于"
        }
    }
}


struct PanelRow: Identifiable {
    let position: Position
    let view: PositionView
    let plan: Plan?
    let executed: Set<String>
    let next: PlanLevel?
    let hit: PlanLevel?
    var id: Int64 { position.id }
}

@MainActor
final class AppState: ObservableObject {
    @Published var portfolio: Portfolio?
    @Published var plans: [Int64: Plan] = [:]
    @Published var quotes: [String: Quote] = [:]
    /// 菜单栏指数条：key 为东方财富 secid（如 1.000001）。
    @Published var indexQuotes: [String: Quote] = [:]
    @Published var rows: [PanelRow] = []
    /// 观察标的行：不估值，只用于展示与提醒。
    @Published var watchRows: [PanelRow] = []
    @Published var expanded: Int64?
    @Published var lastUpdated: Date?
    @Published var quoteError: String?
    @Published var error: String?
    @Published var alerts: [CarapaceCore.Alert] = []
    @Published var muted: Bool {
        didSet { CarapaceDefaults.store.set(muted, forKey: "muted") }
    }
    @Published var systemNotifications: Bool {
        didSet {
            CarapaceDefaults.store.set(systemNotifications, forKey: "systemNotifications")
            if systemNotifications { Task { await NotificationService.shared.requestAuthorization() } }
        }
    }
    /// 分类通知开关，缺省为开；只影响之后新触发的提醒。
    @Published var notifyCategories: [String: Bool] {
        didSet { CarapaceDefaults.store.set(notifyCategories, forKey: "notifyCategories") }
    }
    @Published var backgroundCheck: Bool {
        didSet {
            CarapaceDefaults.store.set(backgroundCheck, forKey: "backgroundCheck")
            startBackgroundTimer()
        }
    }
    /// 菜单栏指数条开关；隐藏后不再占用面板高度，行情仍会缓存。
    @Published var showIndexStrip: Bool {
        didSet { CarapaceDefaults.store.set(showIndexStrip, forKey: "showIndexStrip") }
    }
    /// 菜单栏乌龟图标开关；隐藏后从主窗口菜单或设置恢复。
    @Published var showMenuBarIcon: Bool {
        didSet { CarapaceDefaults.store.set(showMenuBarIcon, forKey: "showMenuBarIcon") }
    }
    @Published var eastmoneyInterval: TimeInterval {
        didSet { CarapaceDefaults.store.set(eastmoneyInterval, forKey: "eastmoneyInterval") }
    }
    @Published var sinaInterval: TimeInterval {
        didSet { CarapaceDefaults.store.set(sinaInterval, forKey: "sinaInterval") }
    }
    @Published var backgroundMinutes: Double {
        didSet {
            CarapaceDefaults.store.set(backgroundMinutes, forKey: "backgroundMinutes")
            startBackgroundTimer()
        }
    }
    /// 计划到期时是否自动创建复盘待办。
    @Published var autoReview: Bool {
        didSet {
            CarapaceDefaults.store.set(autoReview, forKey: "autoReview")
            if autoReview { ensureDueReviews(force: true) }
        }
    }
    /// 22:30–07:30 不发送系统通知；面板内提醒不受影响。
    @Published var quietHours: Bool {
        didSet { CarapaceDefaults.store.set(quietHours, forKey: "quietHours") }
    }
    /// 单只仓位上限（0...1），超过后在提醒里提示。
    @Published var singlePositionLimit: Double {
        didSet {
            CarapaceDefaults.store.set(singlePositionLimit, forKey: "singlePositionLimit")
            rebuildAlerts()
        }
    }
    /// 招行积存金买卖点差（元/克）。赎回价 = 沪金99 − 点差/2。
    @Published var cmbSpread: Double {
        didSet {
            CarapaceDefaults.store.set(cmbSpread, forKey: "cmbSpread")
            quoteService.cmbSpread = cmbSpread
            refresh()
        }
    }

    /// 港币兑人民币；港股合计按此汇率折算，可在设置里手动改，也会按行情自动更新。
    @Published var hkdRate: Double {
        didSet {
            CarapaceDefaults.store.set(hkdRate, forKey: "hkdRate")
            if abs(oldValue - hkdRate) > 1e-9 { loadPortfolio() }
        }
    }

    @Published var section: AppSection = .overview
    @Published var selectedPositionId: Int64?
    @Published var showPositionDetail = false
    @Published var positionTab: PositionTab = .plan
    @Published var holdTab: HoldTab = .positions
    @Published var reviewTab: ReviewTab = .reviews
    @Published var settingsTab: SettingsTab = .automation
    @Published var selectedReviewId: Int64?
    @Published var selectedMemoryId: Int64?
    @Published var notifPanelOpen = false
    @Published var memories: [MemoryItem] = []
    @Published var reviewRecords: [ReviewRecord] = []
    @Published var drafts: [DraftRecord] = []
    @Published var notifications: [NotificationRecord] = []
    @Published var importPreview: ImportPreview?
    @Published var importError: String?
    @Published var importLoading = false
    @Published var importBatches: [ImportBatch] = []
    @Published var importFileName: String?
    @Published var recentChanges: [Change] = []
    @Published var lastImport: ImportBatch?
    @Published var showIntake = false
    @Published var showImport = false
    @Published var activeSheet: ActiveSheet?
    @Published var toastText: String?

    enum ActiveSheet: Identifiable {
        case trade(Int64)
        case clear(Int64)
        case editPosition(Int64)
        case editPlan(Int64)
        case drafts
        case memory(Int64)
        case importSheet
        case watchEditor(Int64?)
        case convertWatch(Int64)
        var id: String {
            switch self {
            case .trade(let id): return "trade-\(id)"
            case .clear(let id): return "clear-\(id)"
            case .editPosition(let id): return "edit-\(id)"
            case .editPlan(let id): return "plan-\(id)"
            case .drafts: return "drafts"
            case .memory(let id): return "memory-\(id)"
            case .importSheet: return "import"
            case .watchEditor(let id): return "watch-\(id ?? -1)"
            case .convertWatch(let id): return "convert-\(id)"
            }
        }
    }

    let store: Store
    let quoteService: QuoteService
    let updater: UpdateController
    private var timer: Timer?
    private var backgroundTimer: Timer?
    private var lastDataVersion: Int32 = 0

    struct SourceHealth {
        var lastAttempt: Date = .distantPast
        var lastSuccess: Date?
        var consecutiveFailures = 0
        var lastError: String?
        var fetching = false
        var backoff: TimeInterval = 0
    }
    private var health: [QuoteSource: SourceHealth] = [:]
    private var lastAlertFingerprint = ""
    var lastReviewSweep = Date.distantPast
    /// 风格指标不随行情刷新变化，按数据版本缓存。
    var styleCache: StyleMetrics?
    private var eastQuotes: [String: Quote] = [:]
    private var sinaQuotes: [String: Quote] = [:]
    private var cmbQuotes: [String: Quote] = [:]
    private var fundQuotes: [String: Quote] = [:]
    private var previousQuotes: [String: Quote] = [:]
    private var indexFetching = false
    private var lastIndexFetch: Date = .distantPast
    private var hkdFetching = false
    private var lastHKDFetch: Date = .distantPast

    init() throws {
        let defaults = CarapaceDefaults.store
        muted = defaults.bool(forKey: "muted")
        systemNotifications = defaults.object(forKey: "systemNotifications") as? Bool ?? false
        notifyCategories = CarapaceDefaults.notifySettings()
        backgroundCheck = defaults.object(forKey: "backgroundCheck") as? Bool ?? true
        showIndexStrip = defaults.object(forKey: "showIndexStrip") as? Bool ?? true
        showMenuBarIcon = CarapaceDefaults.showMenuBarIcon
        eastmoneyInterval = defaults.object(forKey: "eastmoneyInterval") as? Double ?? 3
        sinaInterval = defaults.object(forKey: "sinaInterval") as? Double ?? 10
        backgroundMinutes = defaults.object(forKey: "backgroundMinutes") as? Double ?? 5
        autoReview = defaults.object(forKey: "autoReview") as? Bool ?? true
        quietHours = defaults.object(forKey: "quietHours") as? Bool ?? false
        singlePositionLimit = defaults.object(forKey: "singlePositionLimit") as? Double ?? 0.2
        cmbSpread = defaults.object(forKey: "cmbSpread") as? Double ?? 5
        hkdRate = defaults.object(forKey: "hkdRate") as? Double ?? 0.85
        store = try Store()
        quoteService = .shared
        updater = UpdateController()
        quoteService.cmbSpread = cmbSpread
        _ = try store.verifyAll()
        load()
        lastDataVersion = (try? store.dataVersion()) ?? 0
        registerObserver()
        startBackgroundTimer()
        if systemNotifications {
            Task { await NotificationService.shared.requestAuthorization() }
        }
    }

    deinit {
        CFNotificationCenterRemoveObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(CarapaceNotify.name as CFString), nil)
    }

    /// CLI 写完设置后发 Darwin 通知，运行中的 App 在这里重新读取偏好。
    func reloadPreferences() {
        let defaults = CarapaceDefaults.store
        let newMuted = defaults.bool(forKey: "muted")
        if newMuted != muted { muted = newMuted }
        let newSystem = defaults.object(forKey: "systemNotifications") as? Bool ?? systemNotifications
        if newSystem != systemNotifications { systemNotifications = newSystem }
        let newCategories = CarapaceDefaults.notifySettings()
        if newCategories != notifyCategories { notifyCategories = newCategories }
        let newBackground = defaults.object(forKey: "backgroundCheck") as? Bool ?? backgroundCheck
        if newBackground != backgroundCheck { backgroundCheck = newBackground }
        let newIndex = defaults.object(forKey: "showIndexStrip") as? Bool ?? showIndexStrip
        if newIndex != showIndexStrip { showIndexStrip = newIndex }
        let newMenuBarIcon = CarapaceDefaults.showMenuBarIcon
        if newMenuBarIcon != showMenuBarIcon { showMenuBarIcon = newMenuBarIcon }
        let newEast = defaults.object(forKey: "eastmoneyInterval") as? Double ?? eastmoneyInterval
        if newEast != eastmoneyInterval { eastmoneyInterval = newEast }
        let newSina = defaults.object(forKey: "sinaInterval") as? Double ?? sinaInterval
        if newSina != sinaInterval { sinaInterval = newSina }
        let newMinutes = defaults.object(forKey: "backgroundMinutes") as? Double ?? backgroundMinutes
        if newMinutes != backgroundMinutes { backgroundMinutes = newMinutes }
        let newReview = defaults.object(forKey: "autoReview") as? Bool ?? autoReview
        if newReview != autoReview { autoReview = newReview }
        let newQuiet = defaults.object(forKey: "quietHours") as? Bool ?? quietHours
        if newQuiet != quietHours { quietHours = newQuiet }
        let newLimit = defaults.object(forKey: "singlePositionLimit") as? Double ?? singlePositionLimit
        if newLimit != singlePositionLimit { singlePositionLimit = newLimit }
        let newSpread = defaults.object(forKey: "cmbSpread") as? Double ?? cmbSpread
        if newSpread != cmbSpread { cmbSpread = newSpread }
        let newRate = defaults.object(forKey: "hkdRate") as? Double ?? hkdRate
        if newRate != hkdRate { hkdRate = newRate }
        let newAutoCheck = defaults.object(forKey: "autoCheck") as? Bool ?? updater.autoCheck
        if newAutoCheck != updater.autoCheck { updater.autoCheck = newAutoCheck }
        let newAutoUpdate = defaults.object(forKey: "autoUpdate") as? Bool ?? updater.autoUpdate
        if newAutoUpdate != updater.autoUpdate { updater.autoUpdate = newAutoUpdate }
    }

    /// 完整重载：持仓投影 + 复盘/记忆/草稿/通知。
    /// 行情刷新只需要 loadPortfolio()，避免每 3 秒读一遍 V5 表。
    func load() {
        styleCache = nil
        loadPortfolio()
        loadV5()
    }

    private func loadPortfolio() {
        do {
            let positions = try store.positions()
            var newPlans: [Int64: Plan] = [:]
            var executed: [Int64: Set<String>] = [:]
            for p in positions {
                newPlans[p.id] = try store.plan(positionId: p.id)
                executed[p.id] = try store.executedLevelPrices(positionId: p.id)
            }
            plans = newPlans
            let built = PortfolioBuilder.build(positions: positions, plans: newPlans,
                                               quotes: quotes, executed: executed,
                                               hkdRate: hkdRate)
            portfolio = built
            rows = makeRows(views: built.views, plans: newPlans, executed: executed)

            let watches = try store.watches()
            for w in watches {
                newPlans[w.id] = try store.plan(positionId: w.id)
            }
            plans = newPlans
            watchRows = makeWatchRows(watches: watches, plans: newPlans)
            if let expanded, !rows.contains(where: { $0.id == expanded }) { self.expanded = nil }
            error = nil
            lastDataVersion = (try? store.dataVersion()) ?? lastDataVersion
            rebuildAlerts()
        } catch { self.error = error.localizedDescription }
    }

    var todayTotal: Double? { portfolio?.todayPnl }
    var totalValue: Double { portfolio?.totalValue ?? 0 }

    func weight(_ row: PanelRow) -> Double? {
        row.view.weight.map { $0 * 100 }
    }

    var iconName: String {
        if let first = alerts.first(where: { !$0.isAcknowledged }) { return first.glyph }
        return muted ? "circle.dotted" : "circle"
    }

    var iconTooltip: String {
        if let alert = alerts.first(where: { !$0.isAcknowledged }) {
            return alert.detail.isEmpty ? alert.title : "\(alert.title) · \(alert.detail)"
        }
        return footerStatus
    }

    var footerStatus: String {
        guard !rows.isEmpty else { return "还没有持仓" }
        let trading = rows.contains { MarketHours.isTrading($0.position) }
        guard let lastUpdated else { return trading ? "等待行情" : "已收盘 · 打开面板可获取收盘行情" }
        let clock = Self.clock(lastUpdated)
        if let portfolio, !portfolio.hasCompleteValuation { return "部分行情不可用 · 检查 \(clock)" }
        return trading ? "行情检查 \(clock) · 非交易时间可能为收盘报价" : "已收盘 · 行情检查 \(clock)"
    }

    func notifyEnabled(_ category: NotifyCategory) -> Bool {
        notifyCategories[category.rawValue] ?? true
    }

    func notifyBinding(_ category: NotifyCategory) -> Binding<Bool> {
        Binding(get: { self.notifyEnabled(category) },
                set: { self.notifyCategories[category.rawValue] = $0 })
    }

    func acknowledge(_ id: String) {
        do { try store.acknowledgeAlert(id: id); load() }
        catch { self.error = error.localizedDescription }
    }

    func acknowledgeAll() {
        do { try store.acknowledgeAllAlerts(); load() }
        catch { self.error = error.localizedDescription }
    }

    private func rebuildAlerts() {
        do {
            var signals: [AlertSignal] = []
            let tracked = (rows + watchRows).filter { MarketHours.isTrading($0.position) }
            let sources = Set(tracked.map(\.position.source))
            for source in sources {
                let h = health[source] ?? SourceHealth()
                let missing = tracked.filter { $0.position.source == source && quotes[$0.position.quoteCode] == nil }
                let stale = h.lastSuccess.map { Date().timeIntervalSince($0) > max(3 * interval(for: source), 30) } ?? false
                if h.lastAttempt != .distantPast && (h.consecutiveFailures > 0 || stale || !missing.isEmpty) {
                    let names = missing.isEmpty ? tracked.map(\.position.name) : missing.map(\.position.name)
                    signals.append(AlertSignal(id: "quote:\(source.rawValue)", kind: .quote,
                        title: "\(source.displayName)行情异常：\(names.prefix(2).joined(separator: "、"))",
                        detail: h.lastError ?? "行情时间可能已过期，请手动刷新", category: .quote))
                }
            }
            for row in rows {
                if let hit = row.hit, let quote = row.view.quote {
                    let id = "hit:\(row.position.id):\(hit.id)"
                    signals.append(AlertSignal(id: id, positionId: row.position.id, kind: .hit,
                        title: "\(row.position.name) 触及\(hit.kind == .buy ? "买入" : "卖出")档 \(Fmt.level(hit.price))",
                        detail: "现价 \(Fmt.price(quote.price)) · 行情 \(quote.time)",
                        category: hit.kind == .stop ? .stop : .hit))
                }
                guard let plan = row.plan, let value = plan.nextReview,
                      let date = Dates.parse(value), date < Date() else { continue }
                let days = max(1, Int(Date().timeIntervalSince(date) / 86_400))
                signals.append(AlertSignal(id: "review:\(row.position.id):\(value)",
                    positionId: row.position.id, kind: .review,
                    title: "\(row.position.name) 复盘已到期", detail: "原定 \(value) · 已逾期 \(days) 天",
                    category: .review))
            }
            for row in watchRows {
                let p = row.position
                if let wp = p.watchPrice, wp > 0, let q = row.view.quote, q.price <= wp {
                    let gap = (q.price - wp) / wp * 100
                    signals.append(AlertSignal(id: "watch:\(p.id):\(wp)", positionId: p.id, kind: .watch,
                        title: "观察 · \(p.name) 触及关注价 \(Fmt.level(wp))",
                        detail: "现价 \(Fmt.price(q.price)) · \(Fmt.signedPct(gap)) · 行情 \(q.time)",
                        category: .watch))
                }
                if let hit = row.hit, let quote = row.view.quote {
                    signals.append(AlertSignal(id: "hit:\(p.id):\(hit.id)", positionId: p.id, kind: .hit,
                        title: "观察 · \(p.name) 触及计划买点 \(Fmt.level(hit.price))",
                        detail: "现价 \(Fmt.price(quote.price)) · 行情 \(quote.time)", category: .hit))
                }
            }
            for view in portfolio?.views ?? [] {
                guard let weight = view.weight, weight > singlePositionLimit else { continue }
                signals.append(AlertSignal(
                    id: "risk:\(view.id)", positionId: view.id, kind: .risk,
                    title: "\(view.position.name) 仓位 \(Fmt.pctInt(weight * 100)) 超过上限 \(Fmt.pctInt(singlePositionLimit * 100))",
                    detail: "按当前市值计算；可在设置 → 行情与数据里调整上限", category: .risk))
            }
            // 只按 id + 标题判断是否需要写库；现价/时间这类高频变化不触发每 3 秒一次写事务。
            let fingerprint = signals
                .map { "\($0.id)|\($0.title)" }
                .sorted().joined(separator: "\n")
            if fingerprint != lastAlertFingerprint {
                // 只在提醒首次出现时写通知：已经读过的提醒在条件持续期间不再重复出现，
                // 否则「全部已读」会被下一轮刷新立刻覆盖。条件消失后再次触发会当作新提醒。
                let known = Set(alerts.filter { $0.resolvedAt == nil }.map(\.id))
                try store.syncAlerts(signals)
                lastAlertFingerprint = fingerprint
                for signal in signals where !known.contains(signal.id)
                    && CarapaceDefaults.notifyEnabled(signal.category) {
                    try? store.addNotificationIfNeeded(
                        alertId: signal.id, kind: signal.kind.rawValue,
                        title: signal.title, body: signal.detail,
                        route: route(for: signal))
                }
                notifications = (try? store.notifications(limit: 200)) ?? notifications
            }
            alerts = try store.alerts().sorted {
                let rank: [AlertKind: Int] = [.quote: 0, .risk: 1, .hit: 2, .watch: 3, .review: 4]
                if rank[$0.kind] != rank[$1.kind] { return rank[$0.kind]! < rank[$1.kind]! }
                return $0.firstTriggeredAt < $1.firstTriggeredAt
            }
        } catch { self.error = error.localizedDescription }
    }

    private func route(for signal: AlertSignal) -> String {
        if signal.kind == .review { return "reviews" }
        if let id = signal.positionId { return "position:\(id)" }
        return "overview"
    }

    private func makeRows(views: [PositionView], plans: [Int64: Plan],
                          executed: [Int64: Set<String>]) -> [PanelRow] {
        views.map { view in
            let plan = plans[view.position.id]
            let done = executed[view.position.id] ?? []
            let pending = plan?.levels.filter { $0.kind != .stop && !done.contains($0.id) } ?? []
            let hit = view.quote.flatMap { quote in
                pending.filter { level in
                    guard !(view.isStopActive && level.kind == .buy) else { return false }
                    return level.kind == .buy ? quote.price <= level.price : quote.price >= level.price
                }.min { abs($0.price - quote.price) < abs($1.price - quote.price) }
            }
            return PanelRow(position: view.position, view: view, plan: plan,
                            executed: done, next: view.nextLevel, hit: hit)
        }
    }

    private func makeWatchRows(watches: [Position], plans: [Int64: Plan]) -> [PanelRow] {
        watches.map { p in
            let plan = plans[p.id]
            let buys = plan?.levels.filter { $0.kind == .buy } ?? []
            let quote = quotes[p.quoteCode]
            let next = quote.flatMap { q in
                buys.min { abs($0.price - q.price) < abs($1.price - q.price) }
            }
            let hit = quote.flatMap { q in
                buys.filter { q.price <= $0.price }
                    .min { abs($0.price - q.price) < abs($1.price - q.price) }
            }
            let view = PositionView(position: p, quote: quote, value: nil,
                                    todayPnl: nil, totalPnl: nil, weight: nil,
                                    nextLevel: next, isStopActive: false)
            return PanelRow(position: p, view: view, plan: plan,
                            executed: [], next: next, hit: hit)
        }
        .sorted { a, b in
            let da = watchDistance(a), db = watchDistance(b)
            if da != db { return da < db }
            return a.id < b.id
        }
    }

    /// 排序用：离关注价越近越靠前；没设关注价或没行情的排最后。
    private func watchDistance(_ row: PanelRow) -> Double {
        guard let wp = row.position.watchPrice, wp > 0,
              let price = row.view.quote?.price else { return .greatestFiniteMagnitude }
        return abs(price - wp) / wp
    }

    func startLive() {
        load()
        fetchAll(force: true)
        timer?.invalidate()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopLive() { timer?.invalidate(); timer = nil }
    func refresh() { fetchAll(force: true) }

    private func tick() {
        let version = (try? store.dataVersion()) ?? lastDataVersion
        if version != lastDataVersion { lastDataVersion = version; load() }
        let now = Date()
        // 指数条与持仓无关：即使空仓，面板打开时也按东财节奏刷新。
        if MarketHours.isTrading(.share),
           now.timeIntervalSince(lastIndexFetch) >= max(3, eastmoneyInterval) {
            refreshIndices()
        }
        if MarketHours.isTrading(.hk) { refreshHKD() }
        let positions = (try? store.trackedPositions()) ?? []
        let active = positions.filter { MarketHours.isTrading($0) }
        guard !active.isEmpty else { return }
        for source in QuoteSource.allCases {
            let h = health[source] ?? SourceHealth()
            guard now.timeIntervalSince(h.lastAttempt) >= max(interval(for: source), h.backoff) else { continue }
            scheduleFetch(source, positions: active, now: now)
        }
    }

    private func fetchAll(force: Bool) {
        if force || MarketHours.isTrading(.share) { refreshIndices() }
        if force || MarketHours.isTrading(.hk) { refreshHKD(force: force) }
        let positions = (try? store.trackedPositions()) ?? []
        let active = force ? positions : positions.filter { MarketHours.isTrading($0) }
        guard !active.isEmpty else { return }
        for source in QuoteSource.allCases { scheduleFetch(source, positions: active, now: Date()) }
    }

    /// 菜单栏指数条：单独请求，不依赖持仓列表。
    private func refreshIndices() {
        guard !indexFetching else { return }
        indexFetching = true
        lastIndexFetch = Date()
        Task {
            defer { indexFetching = false }
            guard let quotes = try? await quoteService.fetchIndices(), !quotes.isEmpty else { return }
            indexQuotes = quotes
        }
    }

    /// 港币兑人民币：东方财富 133.HKDCNH，60 秒节流；设置里可手动覆盖。
    func refreshHKD(force: Bool = false) {
        guard !hkdFetching else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastHKDFetch) >= 60 else { return }
        hkdFetching = true
        lastHKDFetch = now
        Task {
            defer { hkdFetching = false }
            guard let quotes = try? await quoteService.fetch(codes: [("133.HKDCNH", .eastmoney)]),
                  let q = quotes["133.HKDCNH"], q.price > 0 else { return }
            hkdRate = min(1.5, max(0.5, q.price))
        }
    }

    private func interval(for source: QuoteSource) -> TimeInterval {
        switch source {
        case .eastmoney: return eastmoneyInterval
        case .sina, .cmb: return sinaInterval
        case .fund: return 60
        }
    }

    private func scheduleFetch(_ source: QuoteSource, positions: [Position], now: Date) {
        var h = health[source] ?? SourceHealth()
        // 系统休眠时在途请求可能永远不返回，超时后允许重新调度，避免永久卡住。
        if h.fetching, now.timeIntervalSince(h.lastAttempt) > 120 { h.fetching = false }
        guard !h.fetching else { return }
        h.fetching = true; h.lastAttempt = now; health[source] = h
        Task { await performFetch(source, positions: positions) }
    }

    private func performFetch(_ source: QuoteSource, positions: [Position]) async {
        let codes = positions.filter { $0.source == source }.map { ($0.quoteCode, source) }
        // 主源失败时，备用源为所有可支持的标的提供报价；主源正常时也保留备用结果。
        let ownCodes = Set(codes.map(\.0))
        let missing = positions.filter { p in
            // 招行折算和基金净值有专用取数逻辑，不参与东财/新浪的互相兜底。
            guard p.source == .eastmoney || p.source == .sina else { return false }
            let cached: Quote?
            switch p.source {
            case .eastmoney: cached = eastQuotes[p.quoteCode]
            case .sina: cached = sinaQuotes[p.quoteCode]
            case .cmb: cached = cmbQuotes[p.quoteCode]
            case .fund: cached = fundQuotes[p.quoteCode]
            }
            return cached == nil
        }
        // 只有东财/新浪能互相兜底；招行折算和基金净值只认自己的标的，
// 不能把别的代码丢进去（否则会给股票/黄金套上基金净值，或反之）。
        let requested: [(code: String, source: QuoteSource)]
        switch source {
        case .eastmoney, .sina:
            // 新浪兜底只适用于 A 股代码；港股/美股/指数的 secid（116.00700 等）不能直接拼成 sina symbol。
            requested = codes + missing.filter {
                $0.market == .cn && !$0.quoteCode.contains(".") && !ownCodes.contains($0.code)
            }.map { ($0.code, source) }
        case .cmb, .fund:
            requested = codes
        }
        // 当期该源没有活跃标的时也必须清掉 fetching，否则这个源会被永久跳过：
        // 晚上只有黄金/基金在交易，A 股源在 tick 里被调度一次后就再也不会刷新。
        guard !requested.isEmpty else {
            var h = health[source] ?? SourceHealth()
            h.fetching = false
            health[source] = h
            return
        }
        do {
            let fetched = try await quoteService.fetch(codes: requested)
            for (code, quote) in fetched where previousQuotes[code] != quote {
                if let p = positions.first(where: { $0.quoteCode == code }) {
                    let prefix = p.kind == .watch ? "观察 · " : ""
                    if let plan = try? store.plan(positionId: p.id) {
                        let executed = (try? store.executedLevelPrices(positionId: p.id)) ?? []
                        for level in plan.levels where !executed.contains(level.id)
                            && AlertEngine.crossed(previous: previousQuotes[code], current: quote, level: level) {
                            let action = level.kind == .buy ? "买入档"
                                : level.kind == .sell ? "卖出档" : "停止买入档"
                            let category: NotifyCategory = level.kind == .stop ? .stop : .hit
                            guard CarapaceDefaults.notifyEnabled(category) else { continue }
                            NotificationService.shared.send(id: "hit:\(p.id):\(level.id)",
                                title: "\(prefix)\(p.name) 触及\(p.kind == .watch ? "计划买点" : action) \(Fmt.level(level.price))",
                                body: level.condition,
                                enabled: systemNotifications && !muted,
                                critical: level.kind == .stop)
                        }
                    }
                    if p.kind == .watch, let wp = p.watchPrice, wp > 0,
                       CarapaceDefaults.notifyEnabled(.watch) {
                        let watchLevel = PlanLevel(id: "watch-\(p.id)", price: wp, kind: .buy,
                                                   quantity: nil, condition: "")
                        if AlertEngine.crossed(previous: previousQuotes[code], current: quote,
                                               level: watchLevel) {
                            NotificationService.shared.send(id: "watch:\(p.id):\(wp)",
                                title: "观察 · \(p.name) 触及关注价 \(Fmt.level(wp))",
                                body: "现价 \(Fmt.price(quote.price))",
                                enabled: systemNotifications && !muted)
                        }
                    }
                }
                previousQuotes[code] = quote
            }
            switch source {
            case .eastmoney: eastQuotes.merge(fetched) { _, new in new }
            case .sina: sinaQuotes.merge(fetched) { _, new in new }
            case .cmb: cmbQuotes.merge(fetched) { _, new in new }
            case .fund: fundQuotes.merge(fetched) { _, new in new }
            }
            var h = health[source] ?? SourceHealth()
            h.fetching = false; h.lastSuccess = Date(); h.lastError = nil
            h.consecutiveFailures = requested.allSatisfy { fetched[$0.0] != nil } ? 0 : 1
            if h.consecutiveFailures > 0 { h.lastError = "部分代码没有有效报价" }
            h.backoff = 0; health[source] = h
            lastUpdated = Date(); rebuildMergedQuotes(); updateQuoteError(); loadPortfolio()
        } catch {
            var h = health[source] ?? SourceHealth()
            h.fetching = false; h.consecutiveFailures += 1; h.lastError = error.localizedDescription
            h.backoff = min(pow(2, Double(h.consecutiveFailures)), 60); health[source] = h
            rebuildMergedQuotes(); updateQuoteError(); loadPortfolio()
        }
    }

    /// 只要还有源报错就显示最后一条；全部恢复后清空。
    private func updateQuoteError() {
        quoteError = health.values.compactMap(\.lastError).first
    }

    private func rebuildMergedQuotes() {
        var merged: [String: Quote] = [:]
        for row in rows + watchRows {
            let key = row.position.quoteCode
            let east = eastQuotes[key]
            let sina = sinaQuotes[key]
            let cmb = cmbQuotes[key]
            let fund = fundQuotes[key]
            switch row.position.source {
            case .eastmoney: merged[key] = east ?? sina ?? cmb ?? fund
            case .sina: merged[key] = sina ?? east ?? cmb ?? fund
            case .cmb: merged[key] = cmb ?? sina ?? east ?? fund
            case .fund: merged[key] = fund
            }
        }
        // 加载时也允许使用缓存，不用持仓状态作为估值前提。
        for (code, quote) in eastQuotes where merged[code] == nil { merged[code] = quote }
        for (code, quote) in sinaQuotes where merged[code] == nil { merged[code] = quote }
        for (code, quote) in cmbQuotes where merged[code] == nil { merged[code] = quote }
        for (code, quote) in fundQuotes where merged[code] == nil { merged[code] = quote }
        if merged != quotes { quotes = merged }
    }

    private func startBackgroundTimer() {
        backgroundTimer?.invalidate(); backgroundTimer = nil
        guard backgroundCheck else { return }
        let t = Timer(timeInterval: max(60, backgroundMinutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.timer == nil, self.backgroundCheck else { return }
                let positions = (try? self.store.trackedPositions()) ?? []
                let active = positions.filter { MarketHours.isTrading($0) }
                guard !active.isEmpty else { return }
                for source in QuoteSource.allCases {
                    self.scheduleFetch(source, positions: active, now: Date())
                }
            }
        }
        RunLoop.main.add(t, forMode: .common); backgroundTimer = t
    }

    private func registerObserver() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(), darwinCallback,
            CarapaceNotify.name as CFString, nil, .deliverImmediately)
    }

    func plan(for id: Int64) -> Plan? { plans[id] }
    func position(id: Int64) -> Position? {
        portfolio?.views.first { $0.id == id }?.position
            ?? watchRows.first { $0.id == id }?.position
    }
    func allPositions(includeClosed: Bool = true) -> [Position] {
        (try? store.positions(includeClosed: includeClosed)) ?? []
    }
    func allWatches() -> [Position] {
        (try? store.watches()) ?? []
    }
    func changes(for id: Int64, limit: Int = 500) -> [Change] {
        (try? store.changes(positionId: id, limit: limit)) ?? []
    }
    func allAlerts() -> [CarapaceCore.Alert] { (try? store.alerts(includeResolved: true)) ?? [] }

    func lookupName(code: String) async -> String? {
        if let name = await quoteService.lookupName(code: code, source: .eastmoney) { return name }
        return await quoteService.lookupName(code: code, source: .sina)
    }

    func lookupName(code: String, source: QuoteSource) async -> String? {
        guard let quotes = try? await quoteService.fetch(codes: [(code, source)]),
              let quote = quotes[code.uppercased()], !quote.name.isEmpty else { return nil }
        return quote.name
    }

    func realizedPnl(for id: Int64) -> Double {
        changes(for: id).reduce(0) { result, change in
            let qty = max(0, (change.qtyBefore ?? 0) - (change.qtyAfter ?? 0))
            switch change.type {
            case .sell, .clear:
                return result + ((change.price ?? 0) - (change.costBefore ?? 0)) * qty - (change.fee ?? 0)
            case .buy: return result
            default: return result
            }
        }
    }

    func addPosition(code: String, name: String, quantity: Double, cost: Double,
                     source: QuoteSource? = nil, unit: UnitKind? = nil,
                     plan: [PlanLevel] = [],
                     description: String? = nil, nextReview: String? = nil,
                     market: InstrumentMarket = .cn,
                     quoteKey: String? = nil) throws -> Position {
        guard quantity > 0 else { throw StoreError.validation("新建实际持仓的数量必须大于 0") }
        let p = try store.addPosition(code: code, name: name, source: source, unit: unit,
                                      quantity: quantity, cost: cost, plan: plan,
                                      description: description, nextReview: nextReview,
                                      market: market, quoteKey: quoteKey)
        afterWrite(); return p
    }

    @discardableResult
    func addWatch(code: String, name: String, source: QuoteSource? = nil,
                  unit: UnitKind? = nil, watchPrice: Double? = nil, note: String? = nil,
                  profileId: String? = nil, plan: [PlanLevel] = [],
                  description: String? = nil,
                  market: InstrumentMarket = .cn, quoteKey: String? = nil) throws -> Position {
        let p = try store.addWatch(code: code, name: name, source: source, unit: unit,
                                   watchPrice: watchPrice, note: note, profileId: profileId,
                                   plan: plan, description: description,
                                   market: market, quoteKey: quoteKey)
        afterWrite(); return p
    }

    func updateWatch(id: Int64, watchPrice: Double?, note: String?,
                     name: String? = nil, profileId: String? = nil) throws {
        try store.updateWatch(id: id, watchPrice: watchPrice, note: note,
                              name: name, profileId: profileId)
        afterWrite()
    }

    func removeWatch(id: Int64) throws {
        try store.removeWatch(id: id)
        if selectedPositionId == id { selectedPositionId = nil; showPositionDetail = false }
        afterWrite()
    }

    @discardableResult
    func convertWatch(id: Int64, quantity: Double, cost: Double,
                      openedAt: String = Dates.today()) throws -> Position {
        let p = try store.convertWatchToHolding(id: id, quantity: quantity,
                                                cost: cost, openedAt: openedAt)
        afterWrite()
        return p
    }

    @discardableResult
    func carryToWatch(positionId: Int64, watchPrice: Double?, note: String?) throws -> Position {
        let p = try store.carryClosedToWatch(positionId: positionId,
                                             watchPrice: watchPrice, note: note)
        afterWrite(); return p
    }

    func recordTrade(id: Int64, side: TradeSide, quantity: Double, price: Double,
                     fee: Double, levelId: String?, note: String?, occurredAt: String) throws {
        _ = try store.recordTrade(positionId: id, side: side, quantity: quantity, price: price,
                                  fee: fee, levelId: levelId, note: note, occurredAt: occurredAt)
        afterWrite()
    }

    func correctPosition(id: Int64, quantity: Double, cost: Double, reason: String) throws {
        guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StoreError.validation("修正持仓必须填写原因")
        }
        guard let current = position(id: id) else { throw StoreError.notFound("持仓不存在") }
        if abs(quantity - current.quantity) > 1e-9 {
            _ = try store.adjustPosition(positionId: id, delta: quantity - current.quantity,
                                         costAfter: cost, price: nil, note: reason)
        } else if abs(cost - current.avgCost) > 1e-9 {
            _ = try store.setCost(positionId: id, cost: cost, note: reason)
        }
        afterWrite()
    }

    func clearPosition(positionId: Int64, price: Double, fee: Double = 0,
                       note: String? = nil) throws -> TradeResult {
        guard let p = position(id: positionId) else { throw StoreError.notFound("持仓不存在") }
        let r = try store.recordTrade(positionId: positionId, side: .sell, quantity: p.quantity,
                                      price: price, fee: fee, note: note)
        afterWrite(); return r
    }

    func updatePlan(positionId: Int64, levels: [PlanLevel], description: String?,
                    nextReview: String?, note: String?, ifVersion: Int?) throws -> PlanUpdateResult {
        let r = try store.updatePlan(positionId: positionId, levels: levels, description: description,
                                     nextReview: nextReview, note: note, author: "user", ifVersion: ifVersion)
        afterWrite(); return r
    }

    func removePlan(positionId: Int64) throws {
        _ = try store.removePlan(positionId: positionId, note: "手动移除")
        afterWrite()
    }

    private func afterWrite() { load() }
    private static func clock(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = MarketHours.zone; f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
