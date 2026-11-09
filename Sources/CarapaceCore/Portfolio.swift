import Foundation

public struct PositionView: Identifiable, Sendable {
    public var id: Int64 { position.id }
    public var position: Position
    public var quote: Quote?
    public var value: Double?
    public var todayPnl: Double?
    public var totalPnl: Double?
    public var weight: Double?
    public var nextLevel: PlanLevel?
    public var isStopActive: Bool
    /// 港股按 HKD 计价；组合合计按此汇率折算成 CNY。
    public var fxRate: Double
    /// 折算成人民币的市值；A股/基金等于 value。
    public var valueCNY: Double?

    public init(position: Position, quote: Quote?, value: Double?,
                todayPnl: Double?, totalPnl: Double?, weight: Double?,
                nextLevel: PlanLevel?, isStopActive: Bool,
                fxRate: Double = 1, valueCNY: Double? = nil) {
        self.position = position
        self.quote = quote
        self.value = value
        self.todayPnl = todayPnl
        self.totalPnl = totalPnl
        self.weight = weight
        self.nextLevel = nextLevel
        self.isStopActive = isStopActive
        self.fxRate = fxRate
        self.valueCNY = valueCNY
    }

    public var price: Double? { quote?.price }
}

public struct Portfolio: Sendable {
    public var views: [PositionView]
    public var totalValue: Double
    public var totalCost: Double
    public var totalPnl: Double?
    public var todayPnl: Double?
    public var hasCompleteValuation: Bool
}

public enum PortfolioBuilder {
    public static func build(positions: [Position], plans: [Int64: Plan],
                             quotes: [String: Quote], executed: [Int64: Set<String>],
                             hkdRate: Double = 1) -> Portfolio {
        var views = positions.map { p in
            let quote = quotes[p.quoteCode]
            let rate = p.market == .hk ? max(0.01, hkdRate) : 1
            let value = quote.map { $0.valuationPrice * p.quantity }
            let valueCNY = value.map { $0 * rate }
            // 基金一天一个净值：今天还没出净值时，这段涨跌属于上一交易日，不计入今日盈亏。
            let today = quote.map { q -> Double in
                if p.source == .fund, !MarketHours.isToday(q.time) { return 0 }
                return (q.valuationPrice - q.prevValuationPrice) * p.quantity
            }
            let total = quote.map { ($0.valuationPrice - p.avgCost) * p.quantity }
            let plan = plans[p.id]
            let done = executed[p.id] ?? []
            let stops = plan?.levels.filter { $0.kind == .stop } ?? []
            let stop = quote.flatMap { q in
                stops.filter { q.price >= $0.price }.min { $0.price < $1.price }
            }
            // 停止买入档生效后，不再把买入档当作「下一档」。
            let next = quote.flatMap {
                nextLevel(plan: plan, price: $0.price, done: done, buyBlocked: stop != nil)
            }
            return PositionView(position: p, quote: quote, value: value,
                                todayPnl: today, totalPnl: total, weight: nil,
                                nextLevel: next, isStopActive: stop != nil,
                                fxRate: rate, valueCNY: valueCNY)
        }
        let complete = views.allSatisfy { $0.value != nil }
        let totalValue = views.reduce(0.0) { $0 + ($1.valueCNY ?? 0) }
        let totalCost = views.reduce(0.0) { $0 + $1.position.costValue * $1.fxRate }
        for i in views.indices {
            guard totalValue > 0, let value = views[i].valueCNY else { continue }
            views[i].weight = value / totalValue
        }
        return Portfolio(views: views, totalValue: totalValue, totalCost: totalCost,
                         totalPnl: complete ? views.reduce(0.0) { $0 + ($1.totalPnl ?? 0) * $1.fxRate } : nil,
                         todayPnl: complete ? views.reduce(0.0) { $0 + ($1.todayPnl ?? 0) * $1.fxRate } : nil,
                         hasCompleteValuation: complete)
    }

    public static func nextLevel(plan: Plan?, price: Double, done: Set<String>,
                                 buyBlocked: Bool = false) -> PlanLevel? {
        guard let plan else { return nil }
        let pending = plan.levels.filter { $0.kind != .stop && !done.contains($0.id) }
        let buys = buyBlocked ? [] : pending.filter { $0.kind == .buy }
        let sells = pending.filter { $0.kind == .sell }
        let buy = buys.filter { $0.price <= price }.max { $0.price < $1.price }
            ?? buys.min { $0.price < $1.price }
        let sell = sells.filter { $0.price >= price }.min { $0.price < $1.price }
            ?? sells.max { $0.price < $1.price }
        switch (buy, sell) {
        case let (b?, s?): return abs(b.price - price) <= abs(s.price - price) ? b : s
        case let (b?, nil): return b
        case let (nil, s?): return s
        default: return nil
        }
    }
}
