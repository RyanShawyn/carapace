import Foundation

public enum ReviewService {
    /// 生成复盘事实 JSON，供 App 新建复盘和 CLI 外部 Agent 共用。
    public static func facts(
        store: Store,
        position: Position,
        quotes: [String: Quote] = [:]
    ) throws -> String {
        var rows: [[String]] = []
        if let date = Dates.parse(position.openedAt) {
            rows.append(["持仓天数", "\(max(1, Int(Date().timeIntervalSince(date) / 86_400))) 天"])
        }
        rows.append(["成本", Fmt.price(position.avgCost)])
        if let quote = quotes[position.quoteCode] {
            rows.append(["现价", Fmt.price(quote.price)])
            rows.append(["今日", Fmt.pct(quote.changePct)])
        }
        if let plan = try store.plan(positionId: position.id) {
            rows.append(["计划档位", "\(plan.levels.count) 档"])
            rows.append(["下次复盘", plan.nextReview ?? "—"])
        }
        let changes = try store.changes(positionId: position.id, limit: 500)
        let trades = changes.filter { $0.type == .buy || $0.type == .sell || $0.type == .clear }
        let planned = trades.filter { $0.levelId != nil || $0.levelPrice != nil }
        rows.append(["计划执行", "\(planned.count) / \(trades.count)"])
        let data = (try? JSONSerialization.data(withJSONObject: rows)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}