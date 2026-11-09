import Foundation

/// App 与 CLI 共用同一套偏好设置域，避免两边的汇率、点差等取值不一致。
public enum CarapaceDefaults {
    public static var suiteName: String {
        ProcessInfo.processInfo.environment["CARAPACE_DEFAULTS_SUITE"] ?? "com.ryan.carapace"
    }

    public static var store: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    public static var hkdRate: Double {
        store.object(forKey: "hkdRate") as? Double ?? 0.85
    }

    public static var cmbSpread: Double {
        store.object(forKey: "cmbSpread") as? Double ?? 5
    }

    /// 分类通知开关；未设置过时一律视为开启，保持旧行为。
    public static func notifyEnabled(_ category: NotifyCategory) -> Bool {
        notifySettings()[category.rawValue] ?? true
    }

    public static func setNotify(_ category: NotifyCategory, _ enabled: Bool) {
        var raw = notifySettings()
        raw[category.rawValue] = enabled
        store.set(raw, forKey: "notifyCategories")
    }

    public static func notifySettings() -> [String: Bool] {
        (store.dictionary(forKey: "notifyCategories") ?? [:]).compactMapValues { $0 as? Bool }
    }
}

/// 可以单独关掉的系统通知类别。
public enum NotifyCategory: String, CaseIterable, Sendable {
    case hit, stop, watch, review, quote, risk, draft, update

    public var title: String {
        switch self {
        case .hit: return "加仓/卖出档到价"
        case .stop: return "停止买入档触发"
        case .watch: return "观察标的到关注价"
        case .review: return "复盘到期"
        case .quote: return "行情异常"
        case .risk: return "仓位超限"
        case .draft: return "计划草稿待确认"
        case .update: return "版本更新提示"
        }
    }

    public var keyword: String {
        switch self {
        case .hit: return "价格穿越"
        case .stop: return "停止买入档"
        case .watch: return "观察关注价"
        case .review: return "复盘到期"
        case .quote: return "行情异常"
        case .risk: return "仓位超限"
        case .draft: return "计划草稿"
        case .update: return "更新提示"
        }
    }
}