import Foundation
import SQLite3

// MARK: - 观察标的

// 观察项复用 positions 表：kind = watch、quantity/avg_cost 恒为 0、status = open。
// 这样行情、计划、分析框架、指标和提醒都能直接复用，组合计算只看 kind = holding。

extension Store {
    @discardableResult
    public func addWatch(code rawCode: String, name rawName: String,
                         source: QuoteSource? = nil, unit: UnitKind? = nil,
                         watchPrice: Double? = nil, note: String? = nil,
                         profileId: String? = nil,
                         openedAt: String = Dates.today(),
                         plan: [PlanLevel] = [], description: String? = nil,
                         market: InstrumentMarket = .cn,
                         quoteKey: String? = nil) throws -> Position {
        let code = normalizeCode(rawCode)
        guard !code.isEmpty else { throw StoreError.validation("代码不能为空") }
        if let watchPrice {
            guard watchPrice.isFinite, watchPrice > 0 else {
                throw StoreError.validation("关注价必须大于 0")
            }
        }
        let key: String?
        if market == .cn {
            key = quoteKey
        } else if let quoteKey {
            key = quoteKey
        } else if market == .hk {
            key = "116.\(code)"
        } else {
            throw StoreError.validation(market == .us
                ? "美股需要先解析交易所" : "指数需要从搜索结果选择")
        }
        let resolvedSource = market == .cn ? (source ?? inferSource(code)) : .eastmoney
        if resolvedSource == .cmb, !isGold(code) {
            throw StoreError.validation("招行积存金只支持黄金代码（含 AU）")
        }
        let resolvedUnit = market == .cn
            ? (unit ?? (resolvedSource == .fund ? .fund : (isGold(code) ? .gram : .share)))
            : .share
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !plan.isEmpty {
            guard plan.allSatisfy({ $0.kind == .buy }) else {
                throw StoreError.validation("观察标的的计划只支持买入档")
            }
            try validate(levels: plan, allowMissingQuantity: true)
        }

        return try write {
            if market.isHoldable, let holding = try openPosition(code: code) {
                throw StoreError.validation("\(holding.name) 已在持仓中，无需重复观察")
            }
            if let existing = try watchPosition(code: code, market: market) {
                throw StoreError.validation("\(existing.name) 已在观察中")
            }
            let profile = profileId
            let stmt = try prepare("""
            INSERT INTO positions
              (code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at,
               kind, note, watch_price, profile_id, market, quote_key)
            VALUES (?, ?, ?, ?, 0, 0, 'open', ?, NULL, 'watch', ?, ?, ?, ?, ?)
            """)
            bind(stmt, 1, code)
            bind(stmt, 2, name.isEmpty ? code : name)
            bind(stmt, 3, resolvedSource.rawValue)
            bind(stmt, 4, resolvedUnit.rawValue)
            bind(stmt, 5, openedAt)
            bind(stmt, 6, note)
            bind(stmt, 7, watchPrice)
            bind(stmt, 8, profile)
            bind(stmt, 9, market.rawValue)
            bind(stmt, 10, key)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let pid = lastID()

            if !plan.isEmpty {
                _ = try insertPlanRow(positionId: pid, version: 1, author: "user",
                                      description: description ?? note, nextReview: nil,
                                      levels: plan, updatedAt: Dates.now())
            }
            return try position(id: pid)!
        }
    }

    /// 编辑观察：传 nil 表示清空关注价/备注；name 为空则保持不变。
    public func updateWatch(id: Int64, watchPrice: Double?, note: String?,
                            name: String? = nil, profileId: String? = nil) throws {
        if let watchPrice {
            guard watchPrice.isFinite, watchPrice > 0 else {
                throw StoreError.validation("关注价必须大于 0")
            }
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        try write {
            guard let p = try position(id: id), p.kind == .watch else {
                throw StoreError.notFound("观察标的不存在")
            }
            let stmt = try prepare("""
            UPDATE positions
            SET watch_price = ?, note = ?,
                name = COALESCE(?, name), profile_id = COALESCE(?, profile_id)
            WHERE id = ? AND kind = 'watch'
            """)
            bind(stmt, 1, watchPrice)
            bind(stmt, 2, note)
            bind(stmt, 3, (trimmedName?.isEmpty == false) ? trimmedName : nil)
            bind(stmt, 4, profileId)
            sqlite3_bind_int64(stmt, 5, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func removeWatch(id: Int64) throws {
        try write {
            guard let p = try position(id: id), p.kind == .watch else {
                throw StoreError.notFound("观察标的不存在")
            }
            try deleteWatchRow(id: id)
        }
    }

    /// 观察转持仓：新建持仓，继承框架、备注、计划与指标，然后删除观察行。
    @discardableResult
    public func convertWatchToHolding(id: Int64, quantity: Double, cost: Double,
                                      openedAt: String = Dates.today()) throws -> Position {
        guard quantity.isFinite, quantity > 0 else { throw StoreError.validation("建仓数量必须大于 0") }
        guard cost.isFinite, cost > 0 else { throw StoreError.validation("建仓成本必须大于 0") }
        guard Dates.isDay(openedAt) else { throw StoreError.validation("建仓日期必须是 YYYY-MM-DD") }

        let accountId = (try? defaultAccount())?.id
        return try write {
            guard let watch = try position(id: id), watch.kind == .watch else {
                throw StoreError.notFound("观察标的不存在")
            }
            guard watch.market.isHoldable else {
                throw StoreError.validation("美股和指数目前只支持观察，暂不支持建仓")
            }
            if let holding = try openPosition(code: watch.code) {
                throw StoreError.validation("\(holding.name) 已有持仓，请直接加仓")
            }
            let watchPlan = try plan(positionId: id)
            let profile: String? = nil
            let note = [watch.note, "\(Dates.today()) 由观察转入持仓"]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "；")

            let stmt = try prepare("""
            INSERT INTO positions
              (code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at,
               kind, note, watch_price, profile_id, market, quote_key, account_id)
            VALUES (?, ?, ?, ?, ?, ?, 'open', ?, NULL, 'holding', ?, NULL, ?, ?, ?, ?)
            """)
            bind(stmt, 1, watch.code)
            bind(stmt, 2, watch.name)
            bind(stmt, 3, watch.source.rawValue)
            bind(stmt, 4, watch.unit.rawValue)
            sqlite3_bind_double(stmt, 5, quantity)
            sqlite3_bind_double(stmt, 6, cost)
            bind(stmt, 7, openedAt)
            bind(stmt, 8, note)
            bind(stmt, 9, profile)
            bind(stmt, 10, watch.market.rawValue)
            bind(stmt, 11, watch.quoteKey)
            if let accountId { sqlite3_bind_int64(stmt, 12, accountId) } else { sqlite3_bind_null(stmt, 12) }
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let pid = lastID()

            _ = try insertChange(positionId: pid, type: .open, qtyBefore: 0, qtyAfter: quantity,
                                 costBefore: 0, costAfter: cost, price: cost, fee: nil,
                                 levelPrice: nil, levelId: nil, planVersion: nil, direction: nil,
                                 planSnapshot: nil, note: "由观察转入", occurredAt: openedAt)

            if let watchPlan, !watchPlan.levels.isEmpty {
                let snapshot = PlanSnapshot(version: 1, author: "user",
                                            description: watchPlan.description,
                                            nextReview: watchPlan.nextReview,
                                            levels: watchPlan.levels)
                _ = try insertPlanRow(positionId: pid, version: 1, author: "user",
                                      description: watchPlan.description,
                                      nextReview: watchPlan.nextReview,
                                      levels: watchPlan.levels, updatedAt: Dates.now())
                _ = try insertChange(positionId: pid, type: .plan, qtyBefore: nil, qtyAfter: nil,
                                     costBefore: nil, costAfter: nil, price: nil, fee: nil,
                                     levelPrice: nil, levelId: nil, planVersion: nil, direction: nil,
                                     planSnapshot: encode(snapshot), note: "由观察转入",
                                     occurredAt: openedAt)
            }

            try copyMetrics(from: id, to: pid)
            try deleteWatchRow(id: id)
            return try position(id: pid)!
        }
    }

    /// 清仓后保留观察：复制原计划中未执行的买入档（数量清空），不删除已清仓行。
    @discardableResult
    public func carryClosedToWatch(positionId: Int64, watchPrice: Double? = nil,
                                   note: String? = nil) throws -> Position {
        if let watchPrice {
            guard watchPrice.isFinite, watchPrice > 0 else {
                throw StoreError.validation("关注价必须大于 0")
            }
        }
        return try write {
            guard let closed = try position(id: positionId), closed.kind == .holding else {
                throw StoreError.notFound("持仓不存在")
            }
            guard closed.status == .closed else {
                throw StoreError.validation("请先清仓，再转为观察")
            }
            let mergedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let existing = try watchPosition(code: closed.code, market: closed.market) {
                let appended = [existing.note, mergedNote]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "；")
                let stmt = try prepare("""
                UPDATE positions SET watch_price = ?, note = ?
                WHERE id = ? AND kind = 'watch'
                """)
                bind(stmt, 1, watchPrice ?? existing.watchPrice)
                bind(stmt, 2, appended.isEmpty ? existing.note : appended)
                sqlite3_bind_int64(stmt, 3, existing.id)
                try stepDone(stmt)
                sqlite3_finalize(stmt)
                return try position(id: existing.id)!
            }

            let oldPlan = try plan(positionId: positionId)
            let done = try executedLevelPrices(positionId: positionId)
            let pendingBuys = (oldPlan?.levels ?? [])
                .filter { $0.kind == .buy && !done.contains($0.id) }
                .map { PlanLevel(id: $0.id, price: $0.price, kind: .buy,
                                 quantity: nil, condition: $0.condition) }
            let profile: String? = nil

            let stmt = try prepare("""
            INSERT INTO positions
              (code, name, source, unit, quantity, avg_cost, status, opened_at, closed_at,
               kind, note, watch_price, profile_id, market, quote_key)
            VALUES (?, ?, ?, ?, 0, 0, 'open', ?, NULL, 'watch', ?, ?, ?, ?, ?)
            """)
            bind(stmt, 1, closed.code)
            bind(stmt, 2, closed.name)
            bind(stmt, 3, closed.source.rawValue)
            bind(stmt, 4, closed.unit.rawValue)
            bind(stmt, 5, Dates.today())
            bind(stmt, 6, mergedNote)
            bind(stmt, 7, watchPrice)
            bind(stmt, 8, profile)
            bind(stmt, 9, closed.market.rawValue)
            bind(stmt, 10, closed.quoteKey)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
            let pid = lastID()

            if !pendingBuys.isEmpty {
                _ = try insertPlanRow(positionId: pid, version: 1, author: "user",
                                      description: oldPlan?.description ?? "清仓后观察",
                                      nextReview: nil, levels: pendingBuys,
                                      updatedAt: Dates.now())
            }
            return try position(id: pid)!
        }
    }

    // MARK: - Helpers

    /// 导入买入产生持仓时消化同代码观察项；在导入事务内调用。
    func consumeWatchOnImport(code: String, into positionId: Int64) throws {
        guard let watch = try watchPosition(code: code) else { return }
        if let note = watch.note, !note.isEmpty {
            let stmt = try prepare("UPDATE positions SET note = ? WHERE id = ?")
            bind(stmt, 1, note)
            sqlite3_bind_int64(stmt, 2, positionId)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
        if let watchPlan = try plan(positionId: watch.id) {
            let stmt = try prepare("SELECT COUNT(*) FROM plans WHERE position_id = ?")
            sqlite3_bind_int64(stmt, 1, positionId)
            let hasPlan = sqlite3_step(stmt) == SQLITE_ROW && sqlite3_column_int64(stmt, 0) > 0
            sqlite3_finalize(stmt)
            if !hasPlan, !watchPlan.levels.isEmpty {
                _ = try insertPlanRow(positionId: positionId, version: 1, author: "user",
                                      description: watchPlan.description,
                                      nextReview: watchPlan.nextReview,
                                      levels: watchPlan.levels, updatedAt: Dates.now())
            }
        }
        try copyMetrics(from: watch.id, to: positionId)
        try deleteWatchRow(id: watch.id)
    }

    func copyMetrics(from: Int64, to: Int64) throws {
        let stmt = try prepare("""
        INSERT INTO position_metrics
          (position_id, key, label, value_text, value_num, unit, source, as_of, note, created_at)
        SELECT ?, key, label, value_text, value_num, unit, source, as_of, note, created_at
        FROM position_metrics WHERE position_id = ?
        """)
        sqlite3_bind_int64(stmt, 1, to)
        sqlite3_bind_int64(stmt, 2, from)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
    }

    /// 删除观察行及其附属数据。调用方负责保证这是 watch 行。
    func deleteWatchRow(id: Int64) throws {
        for table in ["plans", "position_metrics", "alerts", "drafts", "changes"] {
            let stmt = try prepare("DELETE FROM \(table) WHERE position_id = ?")
            sqlite3_bind_int64(stmt, 1, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
        for table in ["reviews"] {
            let stmt = try prepare("UPDATE \(table) SET position_id = NULL WHERE position_id = ?")
            sqlite3_bind_int64(stmt, 1, id)
            try stepDone(stmt)
            sqlite3_finalize(stmt)
        }
        let stmt = try prepare("DELETE FROM positions WHERE id = ? AND kind = 'watch'")
        sqlite3_bind_int64(stmt, 1, id)
        try stepDone(stmt)
        sqlite3_finalize(stmt)
    }
}
