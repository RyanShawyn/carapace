import Foundation

public enum MemoryEngine {
    /// 记忆检索：全局原则、当前框架、当前标的、当前持仓、最近教训。
    /// 个人数据量小，先取全部再按范围和置信度排序，不引入向量库。
    public static func context(store: Store, positionId: Int64?,
                               profileId: String?, code: String?,
                               limit: Int = 20) throws -> [MemoryItem] {
        let all = try store.memories(status: "active", limit: 500)
        let scored = all.map { m -> (MemoryItem, Double) in
            var score = m.confidence
            switch m.scope {
            case .position:
                if let positionId, m.scopeId == String(positionId) { score += 0.5 }
                else { score -= 0.6 }
            case .instrument:
                if let code, m.scopeId == code { score += 0.35 }
                else { score -= 0.4 }
            case .profile:
                if let profileId, m.scopeId == profileId { score += 0.25 }
                else { score -= 0.2 }
            case .global:
                score += 0.1
            }
            if m.kind == .principle || m.kind == .preference { score += 0.1 }
            if m.kind == .hypothesis { score -= 0.15 }
            if let last = Dates.parse(m.lastUsedAt ?? "") {
                let days = Date().timeIntervalSince(last) / 86_400
                score += max(0, 0.1 - days / 1000)
            }
            return (m, score)
        }
        let result = scored.sorted { $0.1 > $1.1 }.prefix(max(1, limit)).map(\.0)
        try? store.touchMemories(ids: result.map(\.id))
        return result
    }

    public static func contextBlock(_ memories: [MemoryItem]) -> String {
        guard !memories.isEmpty else { return "" }
        let lines = memories.enumerated().map { index, m in
            "[M\(index + 1)] \(m.title)：\(m.content)（置信度 \(Int(m.confidence * 100))%）"
        }
        return """
        可引用的历史记忆（只是假设，不是结论；引用时标注编号）：
        \(lines.joined(separator: "\n"))
        """
    }

    @discardableResult
    public static func accept(_ proposals: [MemoryProposal], reviewId: Int64?,
                              store: Store) throws -> [MemoryItem] {
        var out: [MemoryItem] = []
        for p in proposals {
            let item = try store.addMemory(scope: p.scope, scopeId: p.scopeId,
                                           kind: p.kind, title: p.title,
                                           content: p.content, evidence: p.evidence,
                                           confidence: p.confidence, source: "agent",
                                           supersedes: p.supersedes)
            try store.recordMemoryEvent(memoryId: item.id, action: "accepted",
                                        reviewId: reviewId, detail: "from review")
            out.append(item)
        }
        return out
    }
}

public enum StyleEngine {
    public static func compute(store: Store, hkdRate: Double = 1) throws -> StyleMetrics {
        let positions = try store.positions(includeClosed: true)
        let open = positions.filter { $0.status == .open }
        let changes = try store.allChanges(type: nil, limit: 2000)
        let reviews = try store.reviews(includeDone: true, limit: 1000)

        let today = Date()
        let holding = open.compactMap { p -> Double? in
            guard let d = Dates.parse(p.openedAt) else { return nil }
            return today.timeIntervalSince(d) / 86_400
        }
        let holdingAvg = holding.isEmpty ? 0 : holding.reduce(0, +) / Double(holding.count)

        let values = open.map {
            $0.costValue * ($0.market == .hk ? max(0.01, hkdRate) : 1)
        }.sorted(by: >)
        let total = values.reduce(0, +)
        let top3 = values.prefix(3).reduce(0, +)
        let concentration = total > 0 ? top3 / total : 0

        let trades = changes.filter { $0.type == .buy || $0.type == .sell || $0.type == .clear }
        let planned = trades.filter { $0.levelId != nil || $0.levelPrice != nil }
        let planRate = trades.isEmpty ? 1 : Double(planned.count) / Double(trades.count)
        let offPlan = 1 - planRate

        let done = reviews.filter { $0.status == "done" }.count
        let reviewRate = reviews.isEmpty ? 1 : Double(done) / Double(reviews.count)

        var realized: [Int64: Double] = [:]
        for c in changes where c.type == .sell || c.type == .clear {
            let qty = max(0, (c.qtyBefore ?? 0) - (c.qtyAfter ?? 0))
            let pnl = ((c.price ?? 0) - (c.costBefore ?? 0)) * qty - (c.fee ?? 0)
            let rate = positions.first { $0.id == c.positionId }?.market == .hk
                ? max(0.01, hkdRate) : 1
            realized[c.positionId, default: 0] += pnl * rate
        }
        let name: (Int64) -> String = { id in
            positions.first { $0.id == id }?.name ?? "#\(id)"
        }
        let best = realized.max { $0.value < $1.value }
        let worst = realized.min { $0.value < $1.value }

        let pattern: String
        if planRate >= 0.9 {
            pattern = "计划执行稳定"
        } else if offPlan > 0.2 {
            pattern = "计划外交易偏多"
        } else {
            pattern = "分批建仓"
        }

        return StyleMetrics(
            holdingDays: holdingAvg,
            concentration: concentration,
            planRate: planRate,
            offPlanRate: offPlan,
            reviewRate: reviewRate,
            pattern: pattern,
            best: best.map { "\(name($0.key)) \(Fmt.signed($0.value))" } ?? "—",
            worst: worst.map { "\(name($0.key)) \(Fmt.signed($0.value))" } ?? "—"
        )
    }

    public static func narrative(_ m: StyleMetrics) -> String {
        var parts: [String] = []
        if m.concentration > 0.6 {
            parts.append("持仓偏集中，前三大占 \(Fmt.pctInt(m.concentration * 100))")
        } else {
            parts.append("持仓相对分散，前三大占 \(Fmt.pctInt(m.concentration * 100))")
        }
        parts.append("计划执行率 \(Fmt.pctInt(m.planRate * 100))")
        if m.offPlanRate > 0.15 {
            parts.append("计划外交易偏多")
        }
        if m.holdingDays > 0 {
            parts.append("平均持有 \(Int(m.holdingDays.rounded())) 天")
        }
        return "你的风格是「\(m.pattern)」。" + parts.joined(separator: "；") + "。这是从当前流水和复盘计算出的草稿，可以改。"
    }
}
