import Foundation

public enum QuoteSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case eastmoney
    case sina
    /// 招行积存金：不单独取数，按上金所 Au99.99 实时价加减招行点差折算。
    case cmb
    /// 场外基金：新浪基金净值接口，交易日约 20:00 后更新一次。
    case fund

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .eastmoney: return "东方财富"
        case .sina: return "新浪"
        case .cmb: return "招行积存金"
        case .fund: return "基金净值"
        }
    }

    /// 默认刷新间隔，秒。两家都没有公开的频率文档，取保守值。
    public var defaultInterval: TimeInterval {
        switch self {
        case .eastmoney: return 3
        case .sina: return 10
        case .cmb: return 10
        case .fund: return 60
        }
    }

    public var intervalChoices: [TimeInterval] {
        switch self {
        case .eastmoney: return [1, 2, 3, 5, 10]
        case .sina: return [5, 10, 15, 30, 60]
        case .cmb: return [5, 10, 15, 30, 60]
        case .fund: return [60, 300, 600, 1800]
        }
    }

    public var rateNote: String {
        switch self {
        case .eastmoney:
            return "一次请求可批量拉 A 股与沪金；无官方限频说明，建议 2–3 秒，最低 1 秒。"
        case .sina:
            return "需带 Referer，限频较严；建议不低于 10 秒，黄金行情本身 1–2 秒更新。"
        case .cmb:
            return "基准取新浪沪金99（上金所 Au99.99）；现价 = 赎回价 = 基准 − 点差/2，买入价 = 基准 + 点差/2。今日收益按当日 00:00 起算。"
        case .fund:
            return "场外基金用新浪净值接口，一天一个净值，交易日约 20:00 后更新；盘中不变属正常。"
        }
    }
}

public enum UnitKind: String, Codable, Sendable {
    case share
    case gram
    /// 场外基金份额
    case fund

    public var suffix: String {
        switch self {
        case .share: return "股"
        case .gram: return "克"
        case .fund: return "份"
        }
    }

    /// 数量显示小数位：股票整数，黄金 1 位，基金 2 位。
    public var digits: Int {
        switch self {
        case .share: return 0
        case .gram: return 1
        case .fund: return 2
        }
    }
}

public enum PositionStatus: String, Codable, Sendable {
    case open
    case closed
}

public enum PositionKind: String, Codable, Sendable {
    case holding
    case watch
}

/// 标的所属市场。cn 之外目前只支持观察，不参与组合估值。
public enum InstrumentMarket: String, Codable, CaseIterable, Sendable {
    case cn, hk, us, index

    public var displayName: String {
        switch self {
        case .cn: return "A股"
        case .hk: return "港股"
        case .us: return "美股"
        case .index: return "指数"
        }
    }

    public var currency: String {
        switch self {
        case .hk: return "HKD"
        case .us: return "USD"
        case .cn, .index: return "CNY"
        }
    }

    /// 港股通可以建仓；美股和指数目前只支持观察。
    public var isHoldable: Bool { self == .cn || self == .hk }
}

public enum TradeSide: String, Codable, Sendable {
    case buy
    case sell
}

public struct Position: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var code: String
    public var name: String
    public var source: QuoteSource
    public var unit: UnitKind
    public var quantity: Double
    public var avgCost: Double
    public var status: PositionStatus
    public var openedAt: String
    public var closedAt: String?
    /// holding = 持仓；watch = 观察标的（数量与成本恒为 0，不参与组合）。
    public var kind: PositionKind
    public var note: String?
    public var watchPrice: Double?
    /// cn / hk / us / index；非 cn 目前只允许观察。
    public var market: InstrumentMarket
    /// 东方财富 secid（如 116.00700、105.AAPL）；为空时按代码推断。
    public var quoteKey: String?

    public init(id: Int64, code: String, name: String, source: QuoteSource, unit: UnitKind,
                quantity: Double, avgCost: Double, status: PositionStatus,
                openedAt: String, closedAt: String? = nil,
                kind: PositionKind = .holding, note: String? = nil,
                watchPrice: Double? = nil,
                market: InstrumentMarket = .cn, quoteKey: String? = nil) {
        self.id = id
        self.code = code
        self.name = name
        self.source = source
        self.unit = unit
        self.quantity = quantity
        self.avgCost = avgCost
        self.status = status
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.kind = kind
        self.note = note
        self.watchPrice = watchPrice
        self.market = market
        self.quoteKey = quoteKey
    }

    public var isWatch: Bool { kind == .watch }
    /// 行情字典和请求里使用的 key：有 secid 用 secid，否则用代码。
    public var quoteCode: String { quoteKey ?? code }
    public var currency: String { market.currency }
    public var costValue: Double { quantity * avgCost }
    /// 加入观察或建仓后的天数，详情页展示用。
    public var heldDays: Int {
        guard let date = Dates.parse(openedAt) else { return 0 }
        return max(1, Int(Date().timeIntervalSince(date) / 86_400))
    }
}

public struct PlanLevel: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable { case buy, sell, stop }

    public var id: String
    public var price: Double
    public var kind: Kind
    public var quantity: Double?
    public var condition: String

    public init(id: String = UUID().uuidString, price: Double, kind: Kind,
                quantity: Double?, condition: String) {
        self.id = id
        self.price = price
        self.kind = kind
        self.quantity = quantity
        self.condition = condition
    }

    private enum CodingKeys: String, CodingKey { case id, price, kind, quantity, condition }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        price = try c.decode(Double.self, forKey: .price)
        kind = try c.decode(Kind.self, forKey: .kind)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        condition = try c.decodeIfPresent(String.self, forKey: .condition) ?? ""
    }
}

public struct PlanSnapshot: Codable, Equatable, Sendable {
    public var version: Int
    public var author: String
    public var description: String?
    public var nextReview: String?
    public var levels: [PlanLevel]

    enum CodingKeys: String, CodingKey {
        case version, author, description, levels
        case nextReview = "next_review"
    }
}

public struct Plan: Equatable, Sendable {
    public var id: Int64
    public var positionId: Int64
    public var version: Int
    public var author: String
    public var description: String?
    public var nextReview: String?
    public var levels: [PlanLevel]
    public var updatedAt: String

    public init(id: Int64, positionId: Int64, version: Int, author: String,
                description: String?, nextReview: String?, levels: [PlanLevel],
                updatedAt: String) {
        self.id = id
        self.positionId = positionId
        self.version = version
        self.author = author
        self.description = description
        self.nextReview = nextReview
        self.levels = levels
        self.updatedAt = updatedAt
    }

    public var snapshot: PlanSnapshot {
        PlanSnapshot(version: version, author: author, description: description,
                     nextReview: nextReview, levels: levels)
    }
}

public enum ChangeType: String, Codable, CaseIterable, Sendable {
    case open
    case buy
    case sell
    case clear
    case adjust
    case plan
    case cost
}

public struct Change: Identifiable, Equatable, Sendable {
    public var id: Int64
    public var positionId: Int64
    public var type: ChangeType
    public var qtyBefore: Double?
    public var qtyAfter: Double?
    public var costBefore: Double?
    public var costAfter: Double?
    public var price: Double?
    public var fee: Double?
    public var levelPrice: Double?
    public var levelId: String?
    public var planVersion: Int?
    public var direction: String?
    public var planSnapshot: String?
    public var note: String?
    public var occurredAt: String
    public var createdAt: String
}

public struct Quote: Equatable, Sendable {
    public var code: String
    public var name: String
    /// 主展示价：招行积存金是「实时买入价」（客户买入），其他标的即盘面价。
    public var price: Double
    public var prevClose: Double
    public var time: String
    public var source: QuoteSource
    /// 部分渠道有买卖两档（招行积存金）：估值、持仓金额用「实时卖出价」。
    public var sellPrice: Double?
    public var prevSellPrice: Double?

    public init(code: String, name: String, price: Double, prevClose: Double,
                time: String, source: QuoteSource,
                sellPrice: Double? = nil, prevSellPrice: Double? = nil) {
        self.code = code; self.name = name; self.price = price
        self.prevClose = prevClose; self.time = time; self.source = source
        self.sellPrice = sellPrice; self.prevSellPrice = prevSellPrice
    }

    /// 估值价：有卖出档用卖出价，否则用主展示价。
    public var valuationPrice: Double { sellPrice ?? price }
    public var prevValuationPrice: Double { prevSellPrice ?? prevClose }

    public var change: Double { prevClose > 0 ? price - prevClose : 0 }
    public var changePct: Double { prevClose > 0 ? (price - prevClose) / prevClose * 100 : 0 }
}

/// 代码搜索的一条结果：股票、场内基金或场外基金。
public struct SymbolSearchResult: Identifiable, Equatable, Sendable {
    public var code: String
    public var name: String
    /// 展示用市场标签：沪A / 深A / 港股 / 美股 / 指数 / ETF / 场外基金。
    public var market: String
    public var source: QuoteSource
    public var unit: UnitKind
    public var instrumentMarket: InstrumentMarket
    /// 东方财富 secid；A股/ETF/场外基金可为空，按代码推断。
    public var quoteKey: String?

    public var id: String { "\(instrumentMarket.rawValue):\(source.rawValue):\(code)" }
    public var canHold: Bool { instrumentMarket.isHoldable }
    public var currency: String { instrumentMarket.currency }

    public init(code: String, name: String, market: String,
                source: QuoteSource, unit: UnitKind,
                instrumentMarket: InstrumentMarket = .cn,
                quoteKey: String? = nil) {
        self.code = code
        self.name = name
        self.market = market
        self.source = source
        self.unit = unit
        self.instrumentMarket = instrumentMarket
        self.quoteKey = quoteKey
    }
}

/// 菜单栏指数条。secid 是东方财富的市场前缀 + 代码，避免上证 000001 和股票 000001 冲突。
public struct MarketIndex: Identifiable, Equatable, Sendable {
    public var secid: String
    public var shortName: String
    public var fullName: String

    public var id: String { secid }

    public init(secid: String, shortName: String, fullName: String) {
        self.secid = secid
        self.shortName = shortName
        self.fullName = fullName
    }

    public static let panel: [MarketIndex] = [
        MarketIndex(secid: "1.000001", shortName: "上证", fullName: "上证指数"),
        MarketIndex(secid: "0.399001", shortName: "深证", fullName: "深证成指"),
        MarketIndex(secid: "0.399006", shortName: "创业板", fullName: "创业板指"),
        MarketIndex(secid: "1.000688", shortName: "科创50", fullName: "科创50"),
    ]
}

public struct TradeResult: Sendable {
    public var change: Change
    public var position: Position
    public var matchedLevel: PlanLevel?
}

public struct PlanDiff: Codable, Equatable, Sendable {
    public struct Change: Codable, Equatable, Sendable {
        public var from: PlanLevel
        public var to: PlanLevel
    }

    public var added: [PlanLevel]
    public var removed: [PlanLevel]
    public var changed: [Change]

    public var isEmpty: Bool { added.isEmpty && removed.isEmpty && changed.isEmpty }

    public var summary: String {
        var parts: [String] = []
        if !changed.isEmpty { parts.append("改 \(changed.count) 档") }
        if !added.isEmpty { parts.append("新增 \(added.count) 档") }
        if !removed.isEmpty { parts.append("删除 \(removed.count) 档") }
        return parts.isEmpty ? "无改动" : parts.joined(separator: " · ")
    }
}

public struct PlanUpdateResult: Sendable {
    public var plan: Plan
    public var diff: PlanDiff
}

public enum Dates {
    public static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    public static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return f
    }()

    public static func today() -> String { day.string(from: Date()) }
    public static func now() -> String { stamp.string(from: Date()) }
    public static func parse(_ value: String) -> Date? {
        day.date(from: value) ?? stamp.date(from: value)
    }

    public static func isDay(_ value: String) -> Bool {
        day.date(from: value) != nil && day.string(from: day.date(from: value)!) == value
    }
}

public enum Fmt {
    public static func money(_ v: Double, digits: Int = 0) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.\(digits)f", v)
    }

    public static func price(_ v: Double) -> String {
        // 基金净值在 1 元上下、要 4 位；ETF 3 位也能容纳在 2 位里，其余沿用 1–2 位。
        if v >= 100 { return String(format: "%.1f", v) }
        if v > 0 && v < 2 { return String(format: "%.4f", v) }
        return String(format: "%.2f", v)
    }

    public static func level(_ v: Double) -> String {
        String(format: v >= 100 ? "%.0f" : "%.2f", v)
    }

    public static func wan(_ v: Double) -> String {
        String(format: "%.1fw", v / 10000)
    }

    public static func signedMoney(_ v: Double) -> String {
        let raw = String(format: "%.0f", abs(v))
        let grouped = raw.replacingOccurrences(of: "(?<=\\d)(?=(\\d{3})+$)",
                                               with: ",", options: .regularExpression)
        return (v >= 0 ? "+" : "−") + grouped
    }

    public static func signedPct(_ v: Double) -> String {
        String(format: "%@%.1f%%", v >= 0 ? "+" : "−", abs(v))
    }

    public static func pctInt(_ v: Double) -> String {
        String(format: "%.0f%%", v)
    }

    public static func qty(_ v: Double, unit: UnitKind) -> String {
        money(v, digits: unit.digits) + unit.suffix
    }

    public static func pct(_ v: Double) -> String {
        String(format: "%+.2f%%", v)
    }

    public static func signed(_ v: Double, digits: Int = 0) -> String {
        (v >= 0 ? "+" : "-") + money(abs(v), digits: digits)
    }
}
