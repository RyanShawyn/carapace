import Foundation

public enum MarketHours {
    public static let zone = TimeZone(identifier: "Asia/Shanghai")!
    public static let usZone = TimeZone(identifier: "America/New_York")!

    /// 按标的所属市场判断交易时段；港股/美股只看连续交易，不含盘前盘后。
    public static func isTrading(_ market: InstrumentMarket, unit: UnitKind,
                                 at date: Date = Date()) -> Bool {
        switch market {
        case .cn:
            return isTrading(unit, at: date)
        case .index:
            return isTrading(.share, at: date)
        case .hk:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = zone
            let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
            guard let weekday = c.weekday, (2...6).contains(weekday),
                  let hour = c.hour, let minute = c.minute else { return false }
            let mins = hour * 60 + minute
            return (570...720).contains(mins) || (780...960).contains(mins)
        case .us:
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = usZone
            let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
            guard let weekday = c.weekday, (2...6).contains(weekday),
                  let hour = c.hour, let minute = c.minute else { return false }
            let mins = hour * 60 + minute
            return (570...960).contains(mins)
        }
    }

    /// 只关心市场时默认按股票连续交易时段判断（基金/黄金仍用 unit 版本）。
    public static func isTrading(_ market: InstrumentMarket, at date: Date = Date()) -> Bool {
        isTrading(market, unit: .share, at: date)
    }

    public static func isTrading(_ position: Position, at date: Date = Date()) -> Bool {
        isTrading(position.market, unit: position.unit, at: date)
    }

    /// yyyy-MM-dd（上海时区）
    public static func dateString(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 行情时间戳（"yyyy-MM-dd ..." 或纯日期）是否属于今天。
    public static func isToday(_ stamp: String) -> Bool {
        guard stamp.count >= 10 else { return false }
        return stamp.prefix(10) == dateString()
    }

    public static func isTrading(_ unit: UnitKind, at date: Date = Date()) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return false }
        let mins = hour * 60 + minute

        switch unit {
        case .share:
            // 周一至周五 9:15–11:30、13:00–15:00
            guard (2...6).contains(weekday) else { return false }
            return (555...690).contains(mins) || (780...900).contains(mins)
        case .fund:
            // 场外基金一天一个净值，交易日约 20:00 后更新，全天允许查询。
            return (2...6).contains(weekday)
        case .gram:
            // 日盘 9:00–11:30、13:30–15:30；夜盘 20:00–次日 02:30
            let daySession = (2...6).contains(weekday)
                && ((540...690).contains(mins) || (810...930).contains(mins))
            let nightStart = (2...6).contains(weekday) && (1200...1439).contains(mins)
            let nightEnd = (3...7).contains(weekday) && (0...150).contains(mins)
            return daySession || nightStart || nightEnd
        }
    }
}
